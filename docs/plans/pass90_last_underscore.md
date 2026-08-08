# Pass 90 — The Last Underscore: Privacy Decomposed

> **Status:** canon. Final on the character — supersedes Pass 88 §1 and the
> author amendment that restored it. **There is no `_` prefix.**
> **Measured 2026-08-07** by `scripts/pass90_privacy_census.duo`. **5 of 9.**
> All three of the ruling's arguments are **empirically confirmed**. Three of
> privacy's five decomposition targets **do not exist yet**.

---

## 1. The ruling is not aspirational — the magic is one line

Pass 90 argues the leading `_` must go on three grounds. Each is measurable, and
each holds.

**Argument 2 first, because it grounds the others.** The name-sniffing special
case exists, at `src/codegen.zig:20852`, inside `add_module_export`:

```zig
fn add_module_export(..., name: []const u8, force_export: bool) E!void {
    if (name.len == 0) return;
    if (!force_export and name[0] == '_') return;   // <- the magic
    ...
}
```

A binding is excluded from its module's export set **because of its first
character**. Nothing in the projection algebra says so; no operator law derives
it; `@why` could not answer it. This is precisely the de-magicking failure that
killed `@comp`, `satisfies`, and operation namespaces.

**Argument 1 follows immediately.** Because that line controls export, renaming
`_helper` → `helper` **changes the module's surface**. A spelling edit alters
reachability — the one rename in the language that means something, in a
language whose whole recent direction is "names carry only what has no shape".

**Argument 3 is the same fact stated at the graph level.** Under semantic
emission (L4) text is a projection of the graph; a visibility bit living in
byte 0 of an identifier forces the graph to treat identifier bytes as facts.
Visibility is a fact; facts live as facts.

**The sigil defense fails on inspection.** Leading `.` and `:` are *operators in
expression positions* — they appear where an operator can appear and are read by
the grammar. Leading `_` is inside the identifier, read by a string comparison in
codegen. Not the same category.

## 2. What the prefix looks like from inside a module — and why it fooled us

| Row | Form | State |
| --- | --- | --- |
| `P90-1` | `_helper` and `helper` both declare and call, in-module | **LIVE** — identical |
| `P90-2` | interior `_` compound — `shift_limit()` | **LIVE** — pure spelling, preserved |

Within a module the prefix is completely inert: both forms declare, both call,
nothing differs. That is exactly what made it look like harmless convention for
so long. The mechanism only fires at the module boundary, where it is invisible
from the file you are reading.

**Consequence the purge must plan for: dropping the prefix is not a pure
rename.** It *enlarges the export set* of every module it touches. Pass 88's
predicate purge was a rename with collision risk; this one is a surface change
with collision risk.

## 3. The corpus

`lib/std` carries **44 `_`-prefixed bindings**. Dropping the prefix exports all
44. **11 of the base names already exist elsewhere in `lib/std`:**

```
add contains debug emit has is_digit number platform pow reset skip_ws
```

Ten are cross-module and survive if module namespacing holds. **One is
same-file and is a hard error:**

- `lib/std/fs_watch.duo` — `_platform = "poll"` (:26), `_platform =
  detect_platform()` (:46), and `platform(): str` (:630). Dropping the prefix
  puts a value binding and a function of the same name in one module. Per
  GAP-030 the front end will accept the duplicate and fail at the call or in the
  C backend.

Note `is_digit` appears in that collision list, which means `_is_digit` exists
somewhere alongside `is_digit`. Pass 88 independently wants `is_digit` → `digit`.
The two purges interact and must be sequenced, not run concurrently.

## 4. The decomposition — three of five jobs have no owner

The ruling hands privacy's jobs to structures that "already exist". Measured,
two do:

| Job | Owner | State |
| --- | --- | --- |
| single consumer | nested scope (LAW-SCOPE) | **LIVE** (`P90-3`) |
| invariant protection | refinements | **LIVE** (`P90-5`) |
| module contract | protocol face — `mod@api`, satisfaction diffs | SPEC (`P90-4`) |
| invariant protection | sealing | SPEC (`P90-6`) |
| "who uses my internals?" | `dependents(binding)` query | SPEC (`P90-7`) |
| package-internal | topology / `@modules` stage | SPEC (`P90-8`) |

Nesting a helper in its consumer's scope works today, and that is the single
largest category — it is the honest replacement for most of the 44. Refinements
work, so the invariant job is half-covered.

But **the module-contract face, sealing, the dependents query, and the topology
stage are all absent.** For a binding shared by several consumers within a
module, the ruling's answer is "it is module content, unmarked — declare a
protocol face if consumers shouldn't rely on it". That face does not exist, so
the interim state for those bindings is: exported, unmarked, with no way to say
"not part of the contract".

That is a real regression in expressiveness against the *status quo*, and it is
the honest reason to stage this purge rather than run it wholesale. The prefix
was the wrong mechanism; it was not a no-op.

## 5. A contradiction inside the canon

Pass 79 (THE DUO CANON) §I.2 carries both rulings, three paragraphs apart:

- **MOD-1** — "A file IS the module; top-level scope IS the surface; `_name` is
  private."
- **LAW-ONE** — "Names carry ZERO semantics (Pass 90): no `_` prefix — leading
  `_` was a fact wearing a sigil costume."

MOD-1's trailing clause is Pass 88-era text that Pass 90 supersedes. §VII P1
already reads correctly ("visibility = topology (LAW-ONE)"), so the fix is to
strike four words from MOD-1. Filed here rather than patched silently because
the canon is the authority and an agent reading §I.2 top-to-bottom gets opposite
instructions from adjacent laws.

## 6. What an agent should write today

- **No `_` prefix on new bindings.** Nest the helper in its consumer's scope —
  that works now and is the ruling's own first answer.
- **Interior `_` is fine** — `shift_limit`, `read_number`. Pure spelling.
- **Do not bulk-strip the 44 yet.** It is a surface change, not a rename: all 44
  become exported, one (`fs_watch.duo`) is a same-file hard error, and 3 of the
  5 replacement mechanisms don't exist. Strip the single-consumer cases by
  nesting them — that is safe and is most of them.
- **Sequence against Pass 88.** `_is_digit` / `is_digit` / `digit` is touched by
  both purges.

Run `duo run scripts/pass90_privacy_census.duo` before trusting any row.

## 7. Related

- `scripts/pass90_privacy_census.duo` — the gate, floor pinned at the measured 5/9.
- `docs/plans/pass88_lawone.md` — the predicate half; its §1 amendment is
  reversed here.
- `GAP-030` — duplicate declarations, which the `fs_watch.duo` collision hits.
- `src/codegen.zig:20852` — the mechanism. One conditional.
