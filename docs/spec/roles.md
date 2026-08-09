# The role taxonomy — ONE taxonomy, and what it is checked against

**Epoch 2.** Sources, in precedence order: `CLAUDE.md` §0d (H-1…H-8, Passes
113-118) · `CLAUDE.md` §0g (G-TOTAL + fine splits, Passes 117-119) ·
`docs/spec/grammar.md` (Pass 108, **normative**) · `docs/spec/pass100.md` §2 and
§4 · `gaps/GAP-078.md` (the ruling that merged two taxonomies into this one).

This file used to be a rival enumeration. It is not one any more. **The taxonomy
is the table in `tools/lsp/src/highlight.duo`**, which is data, is the source of
`highlights.scm` and the LSP legend, and is convicted by two corpora on every
run of `zig build highlight-corpus`. This document is its prose face: what the
rows mean, which rule decides each discrimination, and where the law is still
silent. Where this file and that table disagree, **the table wins and the
disagreement is a finding filed against this file**, because the table is the
thing the front ends actually read.

## 0. What was ruled, so the history does not have to be re-read

Two role implementations landed in this tree on the same day, both citing §0d
and §0g, and they disagreed on six questions. `gaps/GAP-078.md` ruled all six.
The outcome, and it is not a compromise — each question went to whichever side
had the argument:

| question | ruling | which side |
|---|---|---|
| `:` copula vs invoke | **grammar.md R1**; spacing only RENDERS it | this document's §5.1 |
| the closed count, 17 or 18 | **neither** — H-2 rules CLOSURE and no number | neither |
| the ordinary binding | **`place`**, blue, heavy at definition | the projector's |
| the string role's name | **`literal`** | this document's |
| §0g's fine splits | **cards within roles**, except where the law names a role | the projector's |
| the `ambiguous` member | **kept** — an uncountable ambiguity is not a zero | this document's |

`scripts/role_scan.duo` is DELETED. Its corpus is not: the seven fixtures under
`fixtures/highlight/*.duo` and their span sidecars are now read by
`scripts/highlight.duo` in the surviving vocabulary, which is what makes the
rename `name`→`place` and `text`→`literal` falsifiable rather than cosmetic.

## 1. The hues — LAW, and citable

H-4: *"hue = semantic SPACE: red law (keywords + copula `:`) · orange descriptor
(+ `@` + union edges) · purple callable (+ invoke `:` + world actions italic +
dnir opcodes + asm mnemonics) · blue value-at-rest (numbers, `.cases`, literals,
registers) · green data-flow (field walks, pipes, witness refs)."*

Five hues. The theme is **github dark (Primer)**, role-mapped (§0d), and it is a
lookup table with five entries and one dim — not one colour per role. Swapping
themes is swapping six hex values.

Three axes ride on top of hue and are *not* hues:

- **H-3** definition and use share a hue; **definition adds WEIGHT**.
- **H-5** weight = DEFINITION everywhere; **italic = AMBIENT/FOREIGN** — "all
  foreign source is italic; the trust boundary is typographic."
- **H-6** luminance = **surprisal**: faint = inferable, never absent.
- §0g: **walk-writes underlined**.

A rendered token is therefore `(role, card, weight, italic, underline,
luminance)`. Only the first two come out of the taxonomy table; the rest are
columns of the role's row.

## 2. CLOSURE, not a count

**H-2 as the rendered spec states it is "the role set is closed" — with no
number.** "18" was a summary artifact, and this document's own §4 used to do
arithmetic against it. Both files have stopped asserting a number. What CLOSURE
means operationally, and what `closed()` in the projector actually checks before
it will print anything:

- the set is non-empty and ENUMERATED — it is a table, not a predicate;
- no role name and no role code is claimed twice;
- every role carries a hue a hue row defines, a rule a rule row expands, a
  tree-sitter capture, and at least one CARD;
- every card refines a role that exists;
- **exactly one DIAGNOSTIC member exists** (see §3).

The count is a BINDING. It is reported by `hlmode=table` and by the gate, and it
is checked only against what the renderer needs: the LSP legend must carry
exactly as many token types as the table has roles. A fixed number in that check
was a drift check wearing the wrong clothes, and it broke the moment Pass 118 §4
added a role — which is exactly the event closure is supposed to survive.

## 3. `ambiguous` is not a role, and it is not optional

G-TOTAL gates ambiguity at **0**. A taxonomy with no way to SAY "two candidates"
reports that zero by being unable to count, which is the confident zero §3 of
`CLAUDE.md` warns about. So the table carries one member outside every hue:

```
ambiguous   code `!`   refines no role   never a colour   never counted as coverage
```

It is what the projector emits where two readings are live and no cited rule
separates them, and `fixtures/highlight/mixed/` plus
`fixtures/highlight/union.duo` are the positive controls that prove the
machinery fires. A zero from a corpus that cannot produce a diagnostic is not
evidence.

## 4. The roles

The authority is the table in `tools/lsp/src/highlight.duo`; `hlmode=table`
prints it, and `hlmode=why hlrole=<code>` prints any row's full why-chain — rule
citation, dnir correspondence, tree-sitter capture, and every card. What follows
is the reading, by hue.

**red — law.** `keyword` (the closed terminal set) · `copula` (IS, the ascription
edge; §5.1) · `operator` (`=` binds, `+=` updates, `==` relates, arithmetic, the
unit product — five cards, one hue, because none of them changes the semantic
space) · `layout` (faint: parens by stratum, braces, comma, the literal
delimiter, whitespace — every one of them inferable from the shape of the line).

**orange — descriptor.** `descriptor` (shape space, bold at the declaration) ·
`union` (the union edge; §5.2) · `anchor` (bare `@` and postfix `X@rel`, one role
and two cards; §5.6) · **`retrieve`** (the SPACE WALK; §5.7).

**purple — callable.** `callable` (the realization edge, bold at the declaration;
dnir opcodes and asm mnemonics fold in here, because an opcode and a method call
are the same edge and that is the one-colour-language claim) · `invoke` (the
LAW-CALL projection; §5.1) · `world` (a world action, *italic* under H-5) ·
`foreign` (*italic*: the trust boundary is typographic, and a span with no graph
behind it cannot borrow a role from one).

**blue — value at rest.** `place` (§5.8 — the ordinary binding, and machine
registers, because §0b says registers are places) · `number` · `literal` ·
`case` · `comment` (faint).

**green — data flow.** `walk` (`a.b`, underlined when written; a witness
reference folds in here, because a witness reference is a walk into provenance) ·
`pipe` (a demand stream; §5.2).

## 5. The discriminations, one at a time

### 5.1 `:` — copula vs invoke. **R1 DECIDES.**

Two rules, and **they are not the same rule**:

- §0d: *"copula `:` is SPACED (`x: f64`), invoke `:` is TIGHT (`lx:read`)."*
- `grammar.md` R1: *"IS never takes an argument group; INVOKE always does."*

R1 is the parse rule, it is NORMATIVE (Pass 108), and it is what the projector
implements. §0d's sentence is a statement about what canonical layout EMITS — a
corollary on canonical input, not the decider.

`count:u32` is tight and has no group: R1 says copula, spacing says invoke, and
**spacing is wrong**. `fixtures/highlight/copula.duo` line 3 and
`fixtures/highlight/duon/copula.duo` line 13 both carry that line, from both
corpora, asserted by value at the byte.

The argument that lost is worth keeping, because it was serious: the renderer is
normative, so spacing is a fact about the graph that survives into the byte
stream. **What breaks the tie is TOTALITY.** Spacing survives only for input the
formatter has already touched, and H-6 makes the role function total — it has to
answer for hand-typed, mid-edit, pasted and foreign input. R1 answers there.

The test, which agrees with R1 on all input and with §0d on canonical input:

> `:` immediately followed by a name that is immediately followed by a call
> group (`(`, `{`, or `"`) ⇒ **`invoke`** + **`callable`**. Otherwise ⇒
> **`copula`**, and the copula opens a descriptor edge.

Residual, stated: `lx: read(b)` — spaced, group present. The group is attached to
the shape's own `postfixexpr`, so this is a parameterized descriptor and the test
correctly calls it `copula`. Canonical layout never writes an invoke spaced, so
the residual is unreachable in a canonical file.

### 5.2 `|` — union vs pipe vs bor. **ONE OF THE THREE IS STILL OPEN.**

Three meanings, two hues:

- **union** edge → orange, and it is DECIDABLE: shape position is lexically
  recoverable (`shape → postfixexpr { ("|"|"&") postfixexpr }`, reached from
  `shapedecl → name ":" shape`), so `v: i64 | f64` resolves. The projector
  carries one bit of edge state — *am I on a descriptor edge?* — and that bit is
  set by the copula, which is why the second proof is downstream of the first.
- **pipe** → green. §0g: *"channels = stream places composed by `|`"*. A stream
  needs a stream PLACE, and the one surface fact that opens one is a world
  action, so `sh "ls" | grep("duo")` is a pipe because `sh` opened it.
- **bor** → pass100 §4 lists it (*"bor (integer operands)"*) and **H-4 names no
  hue for it at all.**

`out = xs | ys` opens no stream and is not in shape position. Both readings
stand, no cited rule separates them, and **GAP-078's ruling does not reach this
span** — it ruled six questions and this was not one of them. The projector
DIAGNOSES there rather than defaulting to green, and
`fixtures/highlight/union.duo` is gated as a CONTROL for exactly that reason.
This is the open finding this document owes: **the law needs a rule saying which
reading wins over ordinary operands, or `bor` needs a hue.** Do not close it by
widening the projector.

### 5.3 parens — level vs parameter vs grouping. **ONE ROLE, THREE CARDS.**

All three are `layout`, faint, and the split lives in the card. That follows from
the hue discriminator: none of the three changes the semantic space, and §0g's
demand that they be distinguished is satisfied by a card, which is also what
SPECIFICITY is measured over.

GROUPING is decidable: `primary → "(" expr ")"` versus `postfix → "(" [args]
")"`, and the two differ by whether a postfixexpr precedes the paren.

LEVEL versus PARAMETER is decided by **the LADDER**. §0.5 declares operation-first
at the trie (`read(number) = (lx, b)…`) and calls subject-first at the value
(`lx:read(number)(b)`), and both spellings mark a level the same way — by a
SECOND group immediately following the first. A level is the MARKED form and that
is the mark, so on a laddered line the first name-adjacent group is `strata` and
the rest are `param`.

This document previously called that undecidable and emitted `ambiguous` for
every application group, on the strength of LAW-STRATA calling *both* groups in
`map(symbol)(u32)` levels. That reading is withdrawn as far as the ROLE is
concerned — the role was never in doubt — and the residual is recorded honestly:
the card assignment on `map(symbol)(u32)` says `strata` then `param` where
LAW-STRATA's prose says both are levels. That is a CARD-level disagreement, it is
gated by `fixtures/highlight/paren.duo`, and it is smaller than what it replaced.

### 5.4 call heads

`t:sort(cmp)` gives `sort` as `callable` by 5.1. A bare call head is decided by
the sets the projector carries: a name in the ambient reach (`print`, `sh`, `io`,
`fs`, …) is a `world` action, italic; a name immediately before `{` is rung (a)
of the CONSTRUCTOR LADDER and heads a `descriptor`; a name immediately before `(`
is a `callable`. The residual is the constructor spelled with parens —
`point(3, 4)` — which pass100 §4 makes construction and which is spelled
identically to a call. That one is a real SPECIFICITY finding and it is named
here rather than papered over.

### 5.5 `.name` — case versus walk

`a.b` with a left operand is `walk`, decidable, and it takes the card `write`
(underlined) when it is the left side of a binding rather than a read.

Leading `.name` is R2's one node whose resolution is semantic. What CAN be read
off the surface is the operator to the left: after `=`, `(`, `,` or `|` a
descriptor is expected and the dot opens a CASE; after a word, `)` or `]` it is a
WALK. **At the head of a clause it is neither, and it DIAGNOSES** — R2's own
"neither context ⇒ diagnostic" and G-TOTAL's "two candidates is a mixed-space
DIAGNOSTIC, never a guess" are the same instruction, and
`fixtures/highlight/mixed/dot.duo` line 11 is the control.

Residual, stated: position is what the projector claims. Case-SET MEMBERSHIP —
R2's "against a KNOWN case-set" — remains a graph fact it does not assert.

### 5.6 `@` — bare versus postfix

Decidable, R5: *"Postfix `@` requires a left operand (level 1). Bare `@` is a
primary; immediately followed by `{` it is the enclosing-descriptor constructor —
one production, `"@" [tableliteral]`. **No prefix-`@`-expression production
exists: the grammar cannot express a directive.**"*

All forms are orange, so they are ONE role and the form is the card: `bare` for
`@{…}`, `rel` for `point@polar`. Under the count this used to be an arithmetic
problem; under closure it is a card, which is what the hue discriminator says.

### 5.7 `[ ]` — the SPACE WALK, and where the law overrides the discriminator

**Pass 118 §4 names SPACE WALK its own ROLE**, descriptor-tinted: `to[str]` is
trie navigation, not a bracket. The hue discriminator would have made it a card
inside `descriptor`; the law names a role, so it is a role, spelled `retrieve`
(pass100 §4's own word for `[ ]`, RETRIEVE). **Where the law names a role, take
the law; the discriminator governs only where the law is silent.**

The two cards are separated by the CONTENT's space, which is R5's "operands
select the operator" read off the surface: a lone shape name is descriptor space
(`to[str]` ⇒ card `walk`), a numeric or quoted key is value space (`xs[0]` ⇒ card
`index`), and **a bare name has two candidates — is `i` a descriptor or a
place? — so `xs[i]` DIAGNOSES.** That third case is in the negative control.

### 5.8 the ordinary binding — `place`, and the hole is CLOSED

This document used to call it `name`, leave it UNHUED, and describe it as "the
largest hole": H-4's blue space is "numbers, `.cases`, literals, registers" and an
ordinary binding — `x`, `total`, `lx`, `b` — is none of those four.

**It is `place`: blue, heavy at its definition site.** H-6 makes the role
function TOTAL and an unhued role cannot satisfy a total function — which is
exactly why the unhued reading measured 20% coverage and the hued one measures
100%. A binding IS a place in dnir, `§0b` already says registers are places, and
the spec's own renderer had reached the same answer through H-6's luminance rule
(names carry local meaning and take full ink). **This section is CLOSED.**

## 6. `*.roles` versus MONOGLOT — a spelling ruling

§0d names the golden corpus `fixtures/highlight/*.duo` + `*.roles`. §0f MONOGLOT
says "no non-`.duo` files", the §1 deny list's last row is "any non-`.duo` file",
and `audit100`'s `nonduo` row counts every tracked file not matching
`\.(duo|md)$` against a budget with zero slack. A tracked `*.roles` file would
redden the build on the commit that added it.

Per the epoch-2 conflict protocol — cite the rule, use the canonical spelling,
proceed — the sidecar is spelled **`<fixture>.roles.duo`**. It is the `.roles`
sidecar §0d asks for *and* a `.duo` file, and its content is an ordinary Duo
table literal, so it is data in the language rather than a private text format.

**The corpus is LEXICAL, not compilable.** `paren.duo` does not `duo check`,
because `map` is undeclared and the two-level curried callable that would declare
it is precisely the construct the fixture exists to be sharp about.
`examples/boring/` already establishes the precedent. A golden token corpus asks
what the bytes MEAN to a highlighter, not whether the program runs.

## 7. The two corpora, and why both survive

They assert different things and each catches what the other cannot.

| | `fixtures/highlight/{duon,surface,mixed}/` + `roles/` | `fixtures/highlight/*.duo` + `*.roles.duo` |
|---|---|---|
| granularity | ONE ROLE CODE PER BYTE | SPANS, in role NAMES |
| what it proves | H-6 totality, checked BY LENGTH — a golden line shorter than its source line is a byte with no role | that a role is the one the LAW names, in a vocabulary a reader can check without opening the taxonomy |
| what it cannot catch | a RENAME: the golden stores letters, so `text`→`literal` is invisible in it | a byte that fell out of every span, since it asserts what is there and not what is missing |
| surfaces | duon, dnir, asm, ebnf, foreign | duon only |

Both are run by `zig build highlight-corpus`, against one taxonomy, and
`count:u32` is asserted from both sides.

## 8. What `zig build highlight-corpus` measures

Three gated numbers, per G-TOTAL, plus one reported separately:

1. **coverage** — non-whitespace bytes carrying a role, over every canonical
   non-whitespace byte. **MUST be 100%.** The negative controls' deliberate
   diagnostics leave both sides of the ratio and are printed on their own line;
   counting them against coverage would make the control self-defeating.
2. **ambiguity** — unresolved spans outside the negative controls. **MUST be 0**,
   and the controls' nonzero count is what makes that zero readable.
3. **provenance** — bytes whose role answers `why()` with BOTH a rule citation
   and a dnir edge, over all roled bytes. **MUST be 100%.** This is H-7's
   `(span, role, rule, dnir)` tuple checked by value, through the same `why()`
   the LSP hover serves.
4. **specificity** (Pass 118, reported SEPARATELY and deliberately not folded
   into coverage) — a lexeme taking ONE `(role, card)` pair everywhere it appears
   was decided by its SPELLING and a lexer could have answered it; a lexeme
   taking two or more was decided by its EDGE. The second number is the artifact.
   A taxonomy that assigns every byte a role but tells you nothing a lexer could
   not have told you scores 100% coverage and FAILS.

Every zero is positive-controlled, and the gate ratchets: the floors are
MEASURED, and lowering one needs a sentence saying why the ROW was wrong.

## 9. Falsifier

If a later commit publishes a G-TOTAL percentage that cannot name the taxonomy
behind it, or reintroduces a second role function beside the one in
`tools/lsp/src/highlight.duo`, or greens §5.2 by choosing `pipe` over `bor`
without a rule to cite, this merge was undone by drift rather than by ruling.
