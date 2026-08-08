# Passes 91 & 92 — Identifiers Decompose; Directives Die

> **Status:** canon. Pass 91 revokes the domain-compound exemption; Pass 92
> deletes the directive concept and removes prefix `@` from the grammar.
> **Measured 2026-08-07** by `scripts/census/names.duo`. **5 of 13.**
> **Pass 91's audit scan currently stands at 4,266 distinct violations across
> 14,504 sites in `lib/std` alone.** Prefix `@` is **still in the grammar**.

---

## 1. Pass 91 — the scan, and the honest number

The rule is greppable and absolute: identifiers are single lowercase words;
every interior `_` decomposes to a **LEVEL** (`read_number` → `read(number)`), a
**HOME** (`utf8_valid` → `utf8.valid`), or **CONTEXT** (`shift_limit` → `limit`,
in the scope where `shift` is ambient). `_` survives only inside numbers.

```
grep [a-z]_[a-z] = 0
```

**Measured against that scan:**

| Corpus | Distinct identifiers | Occurrences |
| --- | --- | --- |
| `lib/std` | **4,266** | **14,504** |
| `scripts/` + `examples/` | 1,546 | — |

This is the largest single conformance target in the canon by two orders of
magnitude. Nothing enforces it — `P91-5` confirms a compound still compiles
clean, with no diagnostic.

## 2. Whether the repair is reachable — all 3 destinations are LIVE

A site can only be repaired if its destination form compiles. All three do.

| Destination | Form | State |
| --- | --- | --- |
| **LEVEL** | `scan(number)(1)` | **LIVE** (`P91-1`, `P91-2`) |
| **HOME** | `utf8.valid("a")` | **LIVE** (`P91-3`) |
| **CONTEXT** | `limit()` — pure rename | **LIVE** (`P91-4`) |

**Correction — an earlier revision of this document said the opposite.** It
reported "LEVEL does not compile" and drew the much larger conclusion that Pass
86, Pass 88 and Pass 91 all queue behind one absent operand-selection mechanism.
That was wrong, and the cause is worth recording because it is a measurement
failure, not a language one.

The LEVEL rows were probed using `read` as the family name — taken verbatim from
the canon's own §4 repair table, `read_number → read(number)`. Both failed. But
`read` is unbuildable for an unrelated reason: the C backend emits Duo functions
`static` under their Duo names, so `read` collides with POSIX `read(2)`
(**gap[31]**). Spelled `scan(number)(1)`, the LEVEL form returns `2`.

**So Pass 91 is the most actionable pass on this branch.** Every one of the
14,504 sites has a live destination:

- **CONTEXT** — a pure rename. Free.
- **HOME** — a namespace rearrangement. Free.
- **LEVEL** — `verb(noun)` compiles today, *provided the bare verb is not a libc
  symbol*. That proviso is the only real constraint, and it bites precisely the
  vocabulary LEVEL produces (`read write open close time index send`), because
  LEVEL turns `verb_noun` into a short common verb.

The remaining blocker is scale and judgement — which of LEVEL/HOME/CONTEXT each
site wants is a semantic decision per name — not missing surface.

## 3. Pass 92 — directives die, but prefix `@` has not

The ruling deletes the directive concept: `@assert` → `check(c)`, `@why` →
`why(q)(s)`, `@descriptors` → `graph.descriptors`, `add_module` →
`add(module)(…)`, `@unimplemented(GAP_23)` → `todo(gap[23])`, `@dialect` →
manifest data. The `@` **triad becomes a dyad** — postfix anchors in value
space, bare `@` anchors in scope space, and stage space needs no sigil.

| Row | Form | State |
| --- | --- | --- |
| `P92-7` | bare `@{ ..self, x = 9 }` — the surviving scope anchor | **LIVE** |
| `P92-1` | `check(c)` | SPEC |
| `P92-2` | `why(q)(subject)` | SPEC |
| `P92-3` | `graph.descriptors` | SPEC |
| `P92-4` | `add(module)(…)` | SPEC |
| `P92-5` | `todo(gap[23])` | SPEC |
| `P92-6` | prefix `@` removed from the grammar | **SPEC — still present** |

**A measurement trap worth recording, because an earlier revision of this census
fell into it.** Probing the deletion with `@assert(true)` or `@descriptors`
*appears* to confirm it — both are rejected. But the diagnostic is
`macro expansion error: UnknownMacro`: the **form parsed fine** and the *name*
was unknown. Probing with a macro that exists settles it —

```duo
main(): void
    @comp.assert(true)
    print("live")
end
```
```
ok compile
live
```

Prefix `@` is fully alive, and `@comp.*` is not "deleted/unresolved" either. Two
rows scored `ok` on the bad probe and would have recorded Pass 92 as
substantially more conformant than it is. **A rejection is only evidence when you
know what was rejected.**

None of the five destinations exist as bindings, so the decomposition currently
has nowhere to land. Note `lib/std/check.duo` exists but exports
`std.check.assert` — a *module* with `assert_eq`/`assert_ne` members, which are
themselves Pass 91 violations. The `check` Pass 92 wants is a bare binding, and
bare-name resolution is a compiler mechanism.

## 4. The conformance ledger

Five gates, all green at pinned floors, measuring the passes recorded on this
branch:

| Gate | Score | Blocking mechanism |
| --- | --- | --- |
| `spec_conformance.duo` (Pass 64) | 15/29 | mixed |
| `census/family.duo` (Pass 81) | 10/38 | descriptor member bindings (GAP-025) |
| `census/modes.duo` (Pass 86) | 5/18 | `from` absent; descriptor construction broken |
| `census/lawone.duo` (Pass 88) | 6/19 | sequence surface absent; overloads (GAP-030) |
| `census/privacy.duo` (Pass 90) | 5/9 | 3 of 5 decomposition targets absent |
| `census/names.duo` (Passes 91–92) | 7/14 | prefix `@` present; Pass 92 destinations absent |
| `census/epoch.duo` (Epoch 2 / Pass 93) | 6/14 | enums and result unions do not parse |
| **total** | **49/141** | |

**35% of measured spec rows are implemented.** Read that with the composition in
mind — a meaningful share of the passing rows are controls or vestiges rather
than canonical surface.

Four mechanisms account for most of the rest:

1. **Descriptor member bindings** (GAP-025) — one parse rule gating ~12 rows
   across five sections, and `E2-9`'s `:sibling()` call sits behind it too.
2. **Descriptor construction realization** — `point{…}` emits an undefined
   symbol; the constructor ladder's first rung.
3. **Bare-name resolution for new families** — `check`, `why`, `graph`, `add`,
   `todo`, `clone`, `release`, `meta`, `from`, `sort`, `map` are all ordinary
   undeclared identifiers.
4. **Symbol mangling** (GAP-030, GAP-031) — Duo's namespace and C's are one
   namespace, which blocks overloads *and* makes common verbs unusable.

Note what is **not** on this list any more: operand selection. `scan(number)(1)`
works, so the LEVEL form Pass 86, 88 and 91 all want is available at the language
level; what those passes are missing is the *stdlib surface* declared over it
(`sort`, `take`, `from` as bindings), not the calling convention.

Enum declaration is the newest and sharpest blocker: **the inline case-set does
not parse at all** (`E2-1`, `E2-2`), so Epoch 2 §0.3's default enum form — the
one that replaces the denied `token_kind` companions — has no spelling that
compiles. Result unions (`: t | error`) do not parse either (`E2-5`). Those two
are the epoch's headline forms.

## 5. What an agent should write today

- **New identifiers: one lowercase word.** Free, and it stops the 14,504 growing.
- **Repair LEVEL, HOME and CONTEXT cases when you touch a file.** All three
  destinations compile. The one trap: **do not let a LEVEL repair land on a libc
  verb** — `read`, `write`, `open`, `close`, `time`, `index`, `send` are
  unbuildable as bindings (gap[31]). Check the bare verb before committing to it.
- **Do not write `check`, `why`, `graph.*`, `add(...)`, `todo(...)`.** None
  resolve. `@comp.assert` still works, but it is canon-dead — prefer an ordinary
  call and file the gap.
- **Bare `@{ ..self, x = n }` is safe** and is the one `@` form fully conformant
  with the dyad.
- **Cite gaps as `-- gap[23]`** per Pass 92's respelling.

Run `duo run scripts/census/names.duo` before trusting any row.

## 6. Related

- `scripts/census/names.duo` — the gate, floor pinned at the measured 5/13.
- `docs/plans/pass90_last_underscore.md` — its "interior `_` is fine" guidance
  is superseded here.
- `GAP-030` — overload mangling; blocks the collision half of every rename purge.
- Canon §I.2 — MOD-1 still ends "`_name` is private", contradicting LAW-ONE three
  paragraphs later. Survived the Pass 91/92 regeneration; still four words.
