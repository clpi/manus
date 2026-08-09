# The role taxonomy — what the law fixes, and what it does not

**Epoch 2.** Sources, in precedence order: `CLAUDE.md` §0d (H-1…H-8, Passes
113-115) · `CLAUDE.md` §0g (G-TOTAL + fine splits, Passes 117-119) ·
`docs/spec/grammar.md` (Pass 108, normative) · `docs/spec/pass100.md` §2 and §4.

This file exists because `gaps/GAP-071.md` says G-TOTAL "cannot be measured at
all yet", and the first thing an instrument needs is a written-down scale. It is
**not** a new taxonomy. Everything below is either a citation or a finding that a
citation is missing. Where the law does not decide, this file says so and stops,
because a taxonomy invented here and presented as derived would make every
number `zig build role-scan` prints unfalsifiable.

## 0. The headline

**H-2 says "the 18-role taxonomy is CLOSED". The tree contains no enumeration of
it.** Passes 113-119 have no document in `docs/spec/`; `CLAUDE.md` §0d and §0g
are the entire surviving text. Reading every member the law names, in every hue,
yields **17**. The 18th is unnamed. Separately, §0g's FINE SPLITS require role
distinctions for at least eleven more constructs that no hue claims, and it ends
its own list with the open-ended phrase "per-language leftover roles".

So the taxonomy is simultaneously *asserted closed at 18*, *enumerable to 17*,
and *obliged to cover ≥29*. Those three cannot all hold. §4 does the arithmetic.

## 1. The hues — LAW, and citable

H-4: *"hue = semantic SPACE: red law (keywords + copula `:`) · orange descriptor
(+ `@` + union edges) · purple callable (+ invoke `:` + world actions italic +
dnir opcodes + asm mnemonics) · blue value-at-rest (numbers, `.cases`, literals,
registers) · green data-flow (field walks, pipes, witness refs)."*

Five hues. The theme is **github dark (Primer)**, role-mapped (§0d).

Three axes ride on top of hue and are *not* hues:

- **H-3** definition and use share a hue; **definition adds WEIGHT**.
- **H-5** weight = DEFINITION everywhere; **italic = AMBIENT/FOREIGN** — "all
  foreign source is italic; the trust boundary is typographic."
- **H-6** luminance = **surprisal**: faint = inferable, never absent.
- §0g: **walk-writes underlined**.

A rendered token is therefore `(role, weight, italic, underline, luminance)`.
Only the first component is what H-2 counts.

## 2. The 17 roles the law names

`edge` is what the role projects into the graph. `weight` is the H-5 rule.
`decider` is the lexical test, where the law supplies one; **`—` means the law
supplies no lexical test and the role is only reachable through the graph.**

### red — law

| # | role | edge | weight | decider |
|---|---|---|---|---|
| 1 | `keyword` | control / clause structure | plain | closed terminal set in `grammar.md` §3: `if else while for in return break continue check and or not end` |
| 2 | `copula` | IS — binds a name to a shape | plain | R1 + §0d, see §5.1 — **decidable** |

### orange — descriptor

| # | role | edge | weight | decider |
|---|---|---|---|---|
| 3 | `descriptor` | shape space; the operand kind that addresses a realization edge | **bold at the declaration** (H-3) | shape position: after a copula, or an operand of `\|`/`&` inside a shape (`grammar.md`: `shape → postfixexpr { ("\|"\|"&") postfixexpr }`) |
| 4 | `anchor` | names the subject (bare `@`) or retrieves against it (postfix `X@rel`) | plain | R5 — **decidable**, see §5.6 |
| 5 | `union` | union edge between descriptor operands | plain | `\|` in shape position — **decidable**, see §5.2 |

### purple — callable

| # | role | edge | weight | decider |
|---|---|---|---|---|
| 6 | `callable` | the realization edge | **bold at the declaration** (H-3) | the name of a tight `:name(` invoke — **decidable**. Every other call head is not, see §5.4 |
| 7 | `invoke` | LAW-CALL projection: call at the value, subject-first | plain | R1 + §0d, see §5.1 — **decidable** |
| 8 | `action` | a world action; the world is the ambient subject | *italic* (H-5: ambient) | — LAW-CALL names `sh`, `file.open`, `print` by example, not by rule. Requires the world graph. |
| 9 | `opcode` | a dnir operation | plain | — dnir is a separate surface; no dnir grammar is in the tree |
| 10 | `mnemonic` | a target ISA instruction | plain | — same |

### blue — value at rest

| # | role | edge | weight | decider |
|---|---|---|---|---|
| 11 | `number` | a literal value | plain | `grammar.md` §1 `number` production — **decidable** |
| 12 | `case` | a case of a case-set, by position | plain | — R2 makes this **semantic by law**, see §5.5 |
| 13 | `literal` | a literal value (string, byte, raw) | plain | `grammar.md` §1 `string`/`byte`/`rawstring` — **decidable** |
| 14 | `register` | a place, in dnir/asm rendering | plain | — same surface gap as 9 and 10 |

### green — data flow

| # | role | edge | weight | decider |
|---|---|---|---|---|
| 15 | `walk` | walk from the anchor; data access `a.b` | plain; **underlined when written** (§0g) | `.name` with a left operand — **decidable**. Leading `.name` is not, see §5.5 |
| 16 | `pipe` | a stream place composed by `\|` (§0g: "channels = stream places composed by `\|`") | plain | — not separable from `bor` lexically, see §5.2 |
| 17 | `witness` | a reference to a witness (Pass 104 admission evidence) | plain | — no witness surface exists in the tree (gap[064]: `why` is undeclared) |

## 3. Roles required by the law that no hue claims

§0g: *"FINE SPLITS ARE LAW: `=` **binds** (asserts a fact) vs `+=` **update**
edge vs `==` **relation** query · level parens = strata boundaries vs parameter
parens vs grouping · descriptor braces · walk-writes underlined · comma =
stratify · `[space walk]` · unit `*` · dnir `=`/`->` · per-language leftover
roles."*

Every construct below is a distinct edge the law explicitly refuses to conflate,
and **H-4 assigns none of them a hue**. They are not in the 17. Under H-6 they
must nonetheless have a role, so they are listed here with the names
`scripts/role_scan.duo` emits, and they are counted as **UNHUED** — outside the
closed taxonomy, and therefore *not* credited to coverage.

| emitted | law | decidable? |
|---|---|---|
| `bind` | §0g `=` binds; pass100 §4 "`=` HOLDS … vs `:` IS" | yes, by spelling |
| `update` | §0g `+=` update edge | yes |
| `relation` | §0g `==` relation query | yes |
| `levelparen` | §0g level parens = strata boundaries; LAW-STRATA | **no** — see §5.3 |
| `paramparen` | §0g parameter parens | **no** — see §5.3 |
| `group` | §0g grouping | yes — `grammar.md` `primary → "(" expr ")"` |
| `brace` | §0g descriptor braces; pass100 §4 `{ }` | yes by spelling; the five `{}` meanings are not separated |
| `bracket` | §0g `[space walk]`; pass100 §4 `[ ]` RETRIEVE | yes by spelling |
| `comma` | §0g comma = stratify | yes |
| `operator` | pass100 §4 arithmetic/shift/compare roots; §0g unit `*` | spelling yes; **unit `*` no** — needs the RHS descriptor |
| `bor` | pass100 §4 "`\|` … bor (integer operands)" | **no** — operand space, see §5.2 |
| `comment` | `grammar.md` §1 `comment → "--" to end of line` | yes |
| `name` | **nothing** — see below | n/a |

**`name` is the largest hole and it is not a fine split.** H-4's blue space is
"numbers, `.cases`, literals, registers". An ordinary binding and its use — `x`,
`total`, `lx`, `b` — is none of those four, and no other hue names it either. On
any real Duo file this is the *most common non-whitespace token class in the
file*, and the law as written gives it no hue. This is the single largest
contributor to the coverage number `role-scan` reports.

## 4. The arithmetic, done out loud

Members named by H-4, counted by hue:

```
red     keyword, copula                                        2
orange  descriptor, anchor, union                              3
purple  callable, invoke, action, opcode, mnemonic             5
blue    number, case, literal, register                        4
green   walk, pipe, witness                                    3
                                                              ──
                                                              17
```

H-2 says 18. **Role 18 is unnamed anywhere in the tree.** Two candidates suggest
themselves and neither is derivable:

- `comment` — required by H-6 (comments are non-whitespace bytes) and named by
  no hue.
- `name` — the ordinary binding, above.

Both are guesses. This file does not make them.

**And 18 cannot absorb §3 anyway.** 17 named + 12 unhued-but-required ≥ 29,
before "per-language leftover roles" adds one open-ended family per ingested
language (the Pass 118 roadmap names ts and go). Two readings of §0g were
considered:

- *(A) the fine splits are sub-role modifiers, not roles.* Supported by
  "walk-writes underlined", which is plainly an H-5-style axis. **Rejected for
  the rest**: H-1 says the `:` and `|` splits are "two roles, two colors", and
  §0g lists `=`/`+=`/`==` in the same breath and the same register as those two.
  If a different edge is a different role for `:`, it is a different role for
  `=`.
- *(B) the fine splits are roles.* Then the count is ≥29 and "CLOSED at 18" is
  false as written.

**Ruling: the count in H-2 is UNDERSPECIFIED and roles 8, 9, 10, 12, 14, 16 and
17 are additionally unimplementable today** — `action` needs the world graph,
`opcode`/`mnemonic`/`register` need a dnir and an ISA rendering surface that has
no grammar in the tree, `case` is semantic by R2, `pipe` is not separable from
`bor`, and `witness` has no surface at all (gap[064]). Seven of seventeen roles
cannot be produced by any front end that exists.

`scripts/role_scan.duo` implements the ten that can be, emits the §3 names for
what the law leaves unhued, and refuses to guess anywhere else. -- gap[071]

## 5. The discriminations, one at a time

### 5.1 `:` — copula vs invoke

Two rules, and **they are not the same rule**:

- §0d: *"copula `:` is SPACED (`x: f64`), invoke `:` is TIGHT (`lx:read`)."*
- `grammar.md` R1: *"IS never takes an argument group; INVOKE always does."*

R1 is the parse rule and is total. §0d is a statement about what canonical
layout emits, and it is a *corollary* on canonical input, not the decider.
`count:u32` is tight and has no group: R1 says copula, spacing says invoke, and
**spacing is wrong**. `fixtures/highlight/copula.duo` carries that line for
exactly this reason.

The composite test the scanner uses, which agrees with R1 on all input and with
§0d on canonical input:

> `:` immediately followed by a name that is immediately followed by a call
> group (`(`, `{`, or `"`) ⇒ **`invoke`** + **`callable`**. Otherwise ⇒
> **`copula`**.

Residual, stated: `lx: read(b)` — spaced, group present, but the group is
attached to the shape's own `postfixexpr`, so this is a parameterized descriptor
and the test correctly calls it `copula`. Canonical layout never writes an
invoke spaced, so the residual is unreachable in a canonical file.

### 5.2 `|` — union vs pipe vs bor

Three meanings, **two hues, and one of the three has no role at all**:

- union edge → orange (H-4)
- pipe → green (H-4)
- **bor** → pass100 §4 lists it (`"bor (integer operands)"`) and H-4 names no hue.

Shape position is lexically recoverable (`grammar.md`: `shape → postfixexpr
{ ("|"|"&") postfixexpr }`, reached from `shapedecl → name ":" shape`), so
`v: i64 | f64` is decidable as `union`. Outside shape position, pipe and bor are
separated by *operand space* — LAW-STRATA, "infix operand kinds address
realization edges" — which is a semantic question. **Two candidates, no lexical
rule: this is a mixed-space DIAGNOSTIC under G-TOTAL, and the scanner emits
`ambiguous` rather than guessing.**

### 5.3 parens — level vs parameter vs grouping

Grouping *is* decidable: `grammar.md` gives `primary → "(" expr ")"` versus
`postfix → "(" [args] ")"`, and the two differ by whether a postfixexpr precedes
the paren.

Level versus parameter is **not**, and the law says so in its own litmuses:

- LAW-STRATA: *"each independent decision is its own level (`map(symbol)(u32)`;
  litmus: **if the prefix means something, it's a level**)"* — "means something"
  is a graph query.
- LAW-ROLE: *"A descriptor is a level iff it is a choice **operands cannot
  determine**"* — likewise.

The obvious lexical heuristic ("the last group in a spine is the parameters") is
refuted by the law's own example: LAW-STRATA calls *both* groups in
`map(symbol)(u32)` levels. The scanner emits `ambiguous(levelparen|paramparen)`
for every application group and does not pretend otherwise.

### 5.4 call heads

`t:sort(cmp)` gives `sort` as `callable` by 5.1. A bare call head does not:
LAW-CALL permits operation-first spelling for callable-as-value, pass position,
and world actions, and pass100 §4 makes `( )` construction as well
(`descriptors=construction`). So `point(3, 4)` is a constructor — an *orange*
descriptor — and `print(x)` is a *purple* world action, and the two are spelled
identically. `ambiguous(callable|descriptor)`.

This is the Pass 118 **SPECIFICITY** finding in its purest form: the token's
lexical class (`name`) is all a front end can produce, so its role card cannot
beat its lexical class, and that is a finding rather than a pass.

### 5.5 `.name` — case versus walk

`a.b` with a left operand is `walk` (pass100 §4: "data access a.b"). Decidable.

Leading `.name` is **semantic by law**. R2: *"Argument position ⇒ lens over each
element, always. Descriptor-expected position … ⇒ the case. Neither context ⇒
diagnostic. The parser produces ONE node (`anchorref`); resolution is
semantic."* And R2's own descriptor-expected list ("RHS of `==` **against a known
case-set**") is a graph query. `ambiguous(case|walk)`.

Note the law here does something the rest of §0g does not: it *pre-authorises*
the diagnostic. G-TOTAL's "two candidates is a mixed-space DIAGNOSTIC, never a
guess" and R2's "neither context ⇒ diagnostic" are the same instruction.

### 5.6 `@` — bare versus postfix

Decidable, R5: *"Postfix `@` requires a left operand (level 1). Bare `@` is a
primary; immediately followed by `{` it is the enclosing-descriptor constructor
— one production, `"@" [tableliteral]`. **No prefix-`@`-expression production
exists: the grammar cannot express a directive.**"*

All three forms are orange (H-4 puts `@` in the descriptor space with no further
split), so the scanner emits `anchor` for all three and records the form in the
why-chain. **Whether they are one role or three is not stated**; if they are
three, the count in §4 rises to 19 and H-2 is further from closing.

## 6. `*.roles` versus MONOGLOT — a spelling ruling

§0d names the golden corpus `fixtures/highlight/*.duo` + `*.roles`. §0f MONOGLOT
says "no non-`.duo` files", the §1 deny list's last row is "any non-`.duo`
file", and `audit100`'s `nonduo` row counts every tracked file not matching
`\.(duo|md)$` against a budget with zero slack. A tracked `*.roles` file would
redden the build on the commit that added it.

Per the epoch-2 conflict protocol — cite the rule, use the canonical spelling,
proceed — the sidecar is spelled **`<fixture>.roles.duo`**. It is the `.roles`
sidecar §0d asks for *and* a `.duo` file, and its content is an ordinary Duo
table literal, so it is data in the language rather than a private text format.

One consequence outside this file's ownership, recorded rather than done:
`docs/spec/corpus.md` has no rule matching `fixtures/`, and *"a tracked `.duo`
file matching no rule is a gate FAILURE"*. **Committing `fixtures/highlight/**`
requires one line in `docs/spec/corpus.md`.** The right class is `canonical` —
the fixtures are authored Duo that must converge on Pass 100; they are
adversarial about *roles*, not about spelling. Measured against every mechanized
`audit100` row, the seven fixtures plus their seven sidecars plus
`scripts/role_scan.duo` add **2 points, both `snake`**, and both are
`std.script.fs_read` / `fs_exists` — std's own spelling, funnelled through one
helper each in `role_scan.duo` and named in its header. Every other row is 0.

**The corpus is LEXICAL, not compilable.** Six of the seven fixtures pass
`duo check`; `paren.duo` does not, because `map` is undeclared and the two-level
curried callable that would declare it is precisely the construct the fixture
exists to be ambiguous about. `examples/boring/` already establishes the
precedent — ten of its twenty do not compile and the red row is the finding.
A golden token corpus asks what the bytes MEAN to a highlighter, not whether the
program runs.

## 7. What `zig build role-scan` measures

Three numbers, per G-TOTAL:

1. **coverage** — bytes carrying a role from the **closed 17**, over every byte
   that carries a role at all (every non-whitespace byte, plus the whitespace
   *inside* comments and literals, which H-6 gives a role along with the rest of
   its span). `unhued` (§3) and `ambiguous` do not count. G-TOTAL requires 100%.
2. **ambiguity** — spans with two or more candidate roles and no rule that
   decides between them. G-TOTAL requires 0.
3. **mismatch** — spans where the scanner disagrees with the hand-written
   `.roles.duo` sidecar. This is the front-end conformance number and it is the
   only one of the three that is under the scanner author's control. It must be
   0.

The gate fails on any of the three. **It is expected to be RED**, and a green
here today would mean the instrument was built to flatter the law rather than
measure it: coverage cannot reach 100% while `name` has no hue, and ambiguity
cannot reach 0 while `pipe`/`bor`, level/parameter parens, and leading `.name`
are decided by the graph. Both go green by *writing the missing law*, not by
changing the scanner.

## 8. Falsifier

If a later commit shows `role-scan` green without `docs/spec/roles.md` §2 gaining
a hue for `name`, without §3's twelve unhued rows gaining hues, and without a
graph service behind the ambiguous cases, the gate was weakened rather than
satisfied. Check `mismatch` against a deliberately corrupted sidecar before
believing any run — `role_scan.duo` documents both positive controls in its
header and they are the only reason the three numbers above are worth reading.

---

# RESOLVED 2026-08-08 — the rendered spec settles all four open questions

The owner's rendered `duon 0.1` specification page (github-dark, role-mapped,
"this page's renderer implements the taxonomy it specifies") carries the
taxonomy as executable CSS plus a `ROLES` table giving every role its name,
semantic space, rule citation, and dnir correspondence. That is H-7's
`(span, role, rule, dnir)` tuple, shipped. It answers what this file could not
derive.

## 1. The set is LARGER THAN 18, and the extra members are the fine splits

The rendered taxonomy carries roughly forty classes. "18" names the **hue-level
role set**; §0g's fine splits are additional roles in the same stream, each with
its own rule citation — which is what H-1 ("two roles, two colors") requires and
what this file predicted could not be reconciled with a closed 18. Both are true:
the HUE set is closed, the ROLE set is not 18.

## 2. Ordinary names DO have a hue — the largest hole is closed

`t-v` — *value in scope* — renders at full foreground ink, with the rule stated
as **luminance = surprisal (H-6)**: names carry local meaning and take full ink;
structural punctuation is inferable from layout and renders faint. "Dim is a
statement, not an omission."

That was this file's headline gap ("H-4 names no hue for an ordinary binding")
and the reason `role-scan` measured 20% coverage. It resolves without inventing
anything: the hue was always the default foreground.

## 3. Every fine split has a role AND a rule

```
t-bd   '=' binds a fact          a binding asserts; it does not mutate
t-up   '+=' update edge          compound assign = one read-modify fact
t-cmp  '==' relation edge        chains are ONE fact (CHAIN-CMP)
t-pl   level paren               LAW-STRATA: each decision its own level
t-pp   parameter paren           delimits the callable's received places
t-yb   descriptor brace          R2/R3 decide by position
t-cm   comma                     LAW-STRATA: comma = stratify
t-sw   [space walk]              §8: subtrees are tables
t-w2w  walk WRITE (underlined)   writing a place is not reading it
t-sj   bare '.' — the subject    SELF-ZERO: there is no self
t-ch   comparison chain          CHAIN-CMP: one fact, one underline
t-pu   structural punctuation    faint: inferable from layout (H-6)
```

## 4. The `:` discrimination — BOTH rules, at different layers

This file reported §0d (spacing) and `grammar.md` R1 (argument group) as
conflicting. The rendered spec keeps both and assigns them layers:

* **R5** is the semantic rule — *operands select the operator*: `:` is IS in
  binding position, INVOKE postfix.
* **Canonical layout** makes that decision **lexically visible**: the copula is
  spaced (`x: f64`), the invoke is tight (`lx:read`).

So spacing renders a decision it does not make. `count:u32` is then simply
non-canonical input — the formatter's job, not an ambiguity. This file's
recommendation was to demote §0d's sentence; the correct repair is to state it
as a *rendering* consequence, which is what the spec does.

## What this means for `role-scan`

The gate's three numbers are unblocked in principle. Coverage should rise from
20% once `t-v` and the punctuation roles are admitted, and the twelve ambiguity
spans should fall as the fine-split rules land. **Not yet re-measured** — that is
the next run, and the number is what decides, not this paragraph.

## One stale row in the rendered spec

§14.1 still lists **`ward@dominates(wart)` (G-DOM)** as a CI gate. The owner
retired it on 2026-08-08 — *"dominates shouldnt be a thing its just an artifact
of claude"* — and it is gone from `CLAUDE.md` (commit e717f89). What survives is
an ordinary runtime benchmark (`zig build runtime-bench`) publishing losses. The
spec page should drop that bullet.
