# Pass 88 — LAW-ONE: The Underscore Purge

> **Status:** canon, **as amended**. §1 (privacy) is retracted — see below.
> **Measured 2026-08-07** by `scripts/census/lawone.duo`. **6 of 19.**
> The pass splits cleanly into an actionable half and a blocked half, and the
> actionable half **collides at 25 of 71 sites**.

---

## 0. The law, and the amendment

> **LAW-ONE.** Every binding names exactly one semantic concept. Every boundary,
> axis, mode, stage, variant, or visibility an identifier might encode is
> expressed **structurally** — scope, namespace topology, stage, level,
> operand-selected edge, refinement, lens, demand. (The digit separator
> `1_000_000` is exempt: purely visual, zero semantics.)

**SUPERSEDED — see `docs/plans/pass90_last_underscore.md`.** This section
recorded an author amendment ("`_` prefix is OK for private") that restored the
prefix Pass 88 §1 struck. **Pass 90 reverses that restoration permanently: there
is no `_` prefix.** The 44 `_`-prefixed bindings in `lib/std` **are** violations
again, and Pass 90 measured why the question was never cosmetic — the prefix is a
name-sniffing special case at `src/codegen.zig:20852` that silently controls
module export, so dropping it is a *surface change*, not a rename.

Pass 88's own reach is unaffected: the `_` discard binder (§2), stage markers
(§3), and the axis-compound purge (§4). Privacy belongs to Pass 90.

## 1. What splits this pass in two

Unlike Pass 86 — where every repair target was missing and the whole pass was
stop-work — LAW-ONE has a half that needs **no compiler surface at all**:

| Half | Repair | Blocked by |
| --- | --- | --- |
| **§4 predicates** — `is_digit` → `digit` | a pure rename | **collisions only** (§3 below) |
| **§4 operand selection** — `sort_by(.key)` → `sort(.key)` | needs one name with operand-selected edges | the sequence surface, absent (GAP-014) |

Three of the four roles a bare predicate must play already work:

| Row | Form | State |
| --- | --- | --- |
| `P88-1` | guard — `if digit(53)` | **LIVE** |
| `P88-3` | refinement — `byte = i64 & digit` | **LIVE** |
| `P88-14` | selective destructure — `{ name } = user` | **LIVE** |
| `P88-2` | as a value — `p = digit` | SPEC — a named fn is not a value |
| `P88-4` | as a filter operand — `xs:take(digit)` | SPEC — needs the surface |

So "predicates are bare concept nouns serving four roles" is **two-thirds real
today**. The guard and refinement roles work; the value and operand roles need
`P88-2`'s closure gap and the sequence surface respectively.

Every operand-selection row is absent: `sort()`, `sort(.key)`, `max(.score)`,
`take(5)`, `until(space)`, `group(.dept)`, `zip`, `iterate` — all SPEC. Respelling
a surface that does not exist changes nothing, and `spec_conformance.duo` already
measures `map`/`filter`/`push`/`join` as missing. **The respelling is correct and
inert.**

## 2. §2 discards — the denial is unenforced, and `_` reads back

LAW-ONE §2 denies `_` as a binder: "binding a name to ignore it is the
anti-pattern; not binding it is the language."

Measured, `_` is an **ordinary variable**. It binds, and it reads back:

```duo
main(): void
    _ = 5
    print("live")
    print(_)
end
```
```
live
5
```

There is no discard semantics and no diagnostic. Anyone writing `_` as a discard
has a live binding holding a value — the anti-pattern the law names is not merely
permitted, it is indistinguishable from ordinary use. `P88-13` asserts the
rejection and reads MISSING.

Selective destructuring (`{ name } = user`) — the structural mechanism the law
says makes `_` unnecessary — **works** (`P88-14`). So the replacement is real
even though the denial is unenforced.

## 3. §4 predicates — the census, and where the rename collides

`lib/std` carries **71 distinct `is_*` declaration bases** and **72
axis-compound occurrences**:

```
group_by 15 · sort_by 9 · min_by 9 · max_by 9 · order_by 6 · count_by 6
sum_by 4 · key_by 4 · unique_by 3 · proj_while 3 · take_while 2 · drop_while 2
```

**25 of the 71 `is_*` bases already name a top-level binding in `lib/std`:**

```
abs array debug dir eof err fatal float hex integer lower member_name none
number ok optional print running separator some sorted stop table tty upper
```

Some are cross-module and might survive scoping. Four are not, and they are the
ones that matter — `lib/std/result.duo` declares **both halves of four pairs in
one file**:

| line | constructor | line | predicate |
| --- | --- | --- | --- |
| 9 | `ok(value: any)` | 22 | `is_ok(r: any)` |
| 14 | `err(message: any)` | 28 | `is_err(r: any)` |
| 114 | `some(value: any)` | 124 | `is_some(o: any)` |
| 119 | `none()` | 130 | `is_none(o: any)` |

Dropping the prefix redeclares the constructor. Both take one `any`, so no
signature separates them, and `ok(v)` *builds* while `ok(r)` *tests*.

**The law convicts its own repair.** LAW-ONE says a name may not carry two
concepts; `ok` after the rename carries exactly two. The `is_` prefix was not
smuggling "predicate-hood" here — it was the only thing distinguishing a
constructor from its own test. §4's claim that "the USE POSITION already states
it" does not hold when both forms are *called with one argument*.

Two further hazards in the 25: `is_print` → `print` (`unicode.duo`) shadows the
print builtin, and `hash/crc32.duo` binds `table = 0` at top level.

**Overloading cannot rescue it** — measured, and filed as **GAP-030**. The front
end accepts duplicate declarations and resolves overloads; with identical
signatures it correctly reports `ambiguous call to overloaded function 'ok'`
(`P88-16`, **LIVE** — the language does refuse). With *distinct* signatures it
accepts the program and the C backend collides: `conflicting types for 'ok'`,
`redefinition of 'ok__lua'` (`P88-17`, SPEC). The suffix is fixed decoration, not
signature mangling, so typed overloads — the one path that could have made the
other 21 renames safe — are closed.

## 4. §3 stage markers

`check(...)` is not a binding (`P88-15`, SPEC), so "a check runs at the test stage
because it is a check" has nothing to hang on yet. The demotion of `foo_test.duo`
to décor is sound as a *ruling* and costs nothing to adopt — no file needs
renaming — but the stage facts a harness would read do not exist.

## 5. What an agent should write today

- **`_` prefix for privacy is fine.** Amended; `_helper` is idiomatic.
- **Do not bulk-rename `is_*`.** 25 of 71 collide, 4 of them same-file against
  their own constructors, and overloading cannot separate them (GAP-030). The
  safe subset is the 46 non-colliding bases; the other 25 need a ruling on how a
  constructor and its predicate share a noun.
- **Do write new predicates as bare nouns** — `digit`, `space`. The guard and
  refinement roles work today, so a *new* predicate costs nothing and gains two
  of four roles immediately.
- **Do not respell the sequence surface.** `sort(.key)`, `take(digit)`,
  `until(space)`, `group(.dept)` do not exist; `sort_by` etc. are the vestiges
  and they are what runs. Same stop-work as GAP-014.
- **Do not use `_` as a discard.** Not because it is denied — the denial is
  unenforced — but because it silently creates a live binding you can read back.
  Use selective destructuring, which works.

Run `duo run scripts/census/lawone.duo` before trusting any row.

## 6. Related

- `scripts/census/lawone.duo` — the gate, floor pinned at the measured
  6/19. Note the floor was first *guessed* at 6 and measured 5; the gate reported
  a regression that had not happened until two rejection rows were corrected to
  assert empty stdout rather than the `"ABSENT"` sentinel, which can never read
  `ok`. Pin measured numbers.
- `GAP-030` — overloads accepted by the front end, unrepresentable in the backend.
- `docs/plans/pass86_modes_are_descriptors.md` — LAW-ONE subsumes Pass 86 as the
  mode case; both are blocked on surfaces that do not exist, but Pass 88's
  predicate half is not.
- `GAP-014` (CLAUDE.md) — the sequence surface. Every operand-selection row here
  waits on it.
