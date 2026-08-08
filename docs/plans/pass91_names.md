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

## 2. Whether the repair is even reachable — 2 of 3 destinations

A site can only be repaired if its destination form compiles.

| Destination | Form | State |
| --- | --- | --- |
| **HOME** | `utf8.valid("a")` | **LIVE** (`P91-3`) |
| **CONTEXT** | `limit()` — pure rename | **LIVE** (`P91-4`) |
| **LEVEL** | `read(number)(x)` | **SPEC** (`P91-1`, `P91-2`) |

**LEVEL does not compile**, in either the string-keyed or descriptor-operand
spelling. That matters more than the count suggests, because LEVEL is the
destination the canon's own corpus uses: §XIII's `shc/lex.duo` was respelled
`read(number)(lx, b)` and `read(symbol)(lx, b)` in this regeneration. It is also
where the largest class of names goes — every `verb_noun` pair (`read_number`,
`skip_space`, `parse_expr`, `emit_line`) is a LEVEL case.

So the repair splits: **HOME and CONTEXT cases are actionable today** (a HOME
move is a namespace rearrangement; a CONTEXT rename is free). **LEVEL cases are
blocked** on the same missing operand-selection surface that blocks Pass 86's
`from(mode)` and Pass 88's `sort(.key)`. Three passes now queue behind one
absent mechanism.

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
| `census/names.duo` (Passes 91–92) | 5/13 | LEVEL surface absent; prefix `@` present |
| **total** | **46/126** | |

**36% of measured spec rows are implemented.** Read that with the composition in
mind — a meaningful share of the passing rows are controls or vestiges rather
than canonical surface.

Four mechanisms account for most of the rest:

1. **Operand selection / levels** — `read(number)`, `sort(.key)`, `from(mode)`,
   `take(digit)`. Blocks Pass 86, Pass 88's larger half, and Pass 91's LEVEL
   cases. Single highest-value fix in the language.
2. **Descriptor member bindings** (GAP-025) — one parse rule gating ~12 rows.
3. **Descriptor construction realization** — `point{…}` emits an undefined
   symbol; the ladder's first rung.
4. **Bare-name resolution for new families** — `check`, `why`, `graph`, `add`,
   `todo`, `clone`, `release`, `meta`, `from` are all ordinary undeclared
   identifiers.

All four are compiler mechanisms (parser and codegen), not library surface.

## 5. What an agent should write today

- **New identifiers: one lowercase word.** Free, and it stops the 14,504 growing.
- **Repair HOME and CONTEXT cases when you touch a file.** Both destinations
  work. Do not attempt LEVEL cases — `read(number)` does not compile.
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
