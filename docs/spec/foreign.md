# Foreign source, classified: `toolchain@{ foreign = ledger | oracle }`

Epoch 2. This file is **machine-read** by `scripts/foreign_census.duo`
(`zig build foreign-census`). Editing the prose is free; editing a rule line
changes what the census will accept.

## Why this file exists

Pass 105 §4 lists the strategic invariants as anchored protocols on the
toolchain, red in CI until true. One of them is U8:

```
toolchain@{ foreign = ledger | oracle }
```

**There are exactly two licences for a non-Duo file in this repository.**

| class | what it means | where it comes from |
|---|---|---|
| `ledger` | bootstrap debt: it exists because Duo cannot yet build itself without it. It SHRINKS, and it carries a **termination condition** | Pass 103 §7 (G9): `src/*.zig` is "the licensed exception with a termination condition" |
| `oracle` | test equipment: a differential reference, a performance baseline, or an input fixture. It is never on the shipping path and may persist | Pass 103 §5: "foreign compilers remain as *oracles*"; §7: the C differential "is EXPLICITLY LICENSED … C is the oracle, test equipment, never the shipping path" |

Anything else is a **violation**. There is no third class and no silent
default: a tracked foreign file that matches no rule below fails the census.

`scripts/language_census.duo` (`zig build language-census`) COUNTS the same
population and ratchets the sh/py and js debt lines. It answers "how much
foreign code is there"; this file answers "by what right is each piece here".
They are separate steps so that a classification failure and a debt-count
failure are distinguishable — a census that returns one number cannot tell you
which of those went wrong.

## The rule format, and what the gate enforces about it

```
<class>  <path prefix>  <until:… | license:…>
```

- **First match wins**, so order is meaningful: specific prefixes above general
  ones. A prefix ending in `/` matches a directory; one that does not matches
  any path starting with that text.
- A `ledger` row MUST carry `until:` and a condition. *No deletion gate = 
  architectural debt* is the rule `docs/foreign_code_ledger.md` already states;
  the gate makes it mechanical, so a ledger row with no stated end fails the
  census rather than quietly becoming permanent. Every `oracle` row MUST carry
  `license:` and the authority licensing it.
- The census reports `ledger` and `oracle` totals every run. **The ledger total
  is the number Pass 105 §2's enterprise-migration fixture is about** ("the
  bootstrap ledger shrinking with evidence attached"), so it belongs on the
  claims dashboard beside the rest.

## What a file census cannot see, stated rather than hidden

Foreign code also lives INSIDE `.duo` files, as `@c.emit` / `@c.include`
payloads. No extension-based census can see it, and this repository has a
worked example of what that costs: `lib/std/os.duo` and `lib/std/io.duo` obtain
their capability through raw C, which is why gap[061]'s ambient-authority grep
could not find the authority those two modules hold. The census therefore
counts embedded sites as a row of its own and ratchets it. It is `ledger`-class
by construction — it is bootstrap, it has a termination condition (Pass 103's
no-foreign-waist ruling), and it only shrinks.

Two things are stripped before that count, and both were paid for rather than
foreseen. **Comment lines**: the moment the three Pass 105 gates were tracked,
their headers' mentions of `@c.emit` took the count from 236 to 240 and the
ratchet went red over prose. **The census's own source**: adding a diagnostic
that names the token in a string took it to 184. A scanner whose subject is the
text it greps for reports itself, which is the exclusion `audit100` makes for
the identical reason. The honest count is **181**.

## Rules

```
ledger   src/                          until:the self-hosting matrix retires the Zig host (Pass 103 §7, G9)
ledger   build.zig                     until:the build description is written in Duo
ledger   lib/c/                        until:@ffi can dereference C structs and onnx.duo needs no shim
oracle   examples/compile_fail/        license:pass100-corpus — negative fixtures; the foreign text IS the assertion
oracle   examples/pass5/fixtures/      license:pass103-§5 — C headers and sources the FFI path is measured against
oracle   examples/                     license:pass103-§5 — Lua superset inputs, C baselines, and interop references
oracle   benchmarks/                   license:pass103-§5 — performance baselines; the foreign compiler is the referee
oracle   tests/                        license:pass103-§5 — differential fixtures
```

## Unclassified today, and why each is a violation rather than a rule

Two files match nothing above. Each is authored source in another language with
no bootstrap role and no oracle role, which is precisely the definition of debt
this file exists to make visible:

- `ext/tree-sitter-duo/grammar.js` — **PARTIALLY generated** as of `8f07860`:
  `scripts/treesitter_emit.duo` now projects part of it and
  `zig build treesitter-projection` fails unless the tracked file is
  byte-identical to the projection. That is most of the way to a `ledger` row,
  and the rule lands when the projection is TOTAL — a file with authored
  regions is not yet output. See gaps/GAP-049.
- `ext/vscode-duo/extension.js`

Two left the list without a rule being written for them, which is the outcome
this file is for: `docs/theme/custom.js` was deleted, and
`scripts/run_compile_size_benchmark.sh` was rewritten in Duo. The budget was
lowered from 4 to 2 in the same commit that measured it.

A file that becomes genuinely generated belongs in `ledger` with its generator
named and a termination condition. A file that becomes test equipment belongs
in `oracle` with the authority that licenses it. Giving one of them a rule
without changing what it IS is how a two-class law becomes a one-class law.
