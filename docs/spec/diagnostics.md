# duon 0.1 — Diagnostics (Pass 108)

**"Languages are judged in five minutes by one diagnostic"** (Pass 106 §1). Elm
and Rust set the bar. To a newcomer, the first error message *is* the language —
so this page is a language design document, not a formatting guide.

Duo has machinery no incumbent has: facts with provenance, a repair ladder, a
canonicalizer that already knows the target form, and `why` as an ordinary
compiler surface. A diagnostic that only *reports* is leaving all of that on the
floor. Normative until the graph service hosts it.

## 1. The governing rule: repair first

**The fix comes before the lecture.** A diagnostic's first line is what to
write instead. The explanation is what a reader falls through to when the repair
is not obviously right, and the rule is not what they read at all unless they go
looking.

This inverts the incumbent layout, in which the headline is the violation, the
explanation is the body, and the fix — if it appears — is a trailing note. That
order optimizes for the compiler author's model of the program. Repair-first
optimizes for the only thing a reader wants in the first five seconds, which is
to be writing code again.

The three-line test: **a reader who stops after the first line must be able to
fix the program.** If they cannot, the diagnostic is mis-ordered.

Repair-first has a hard consequence for the implementation: **a diagnostic must
carry a repair or explain why it cannot.** "Cannot" is a legitimate answer —
ambiguity is real — but it is a stated one (`no repair: two shapes fit here,
name which`), not an omission.

## 2. Layout

```
┌ severity  rule-id  one-line REPAIR
│
│   file:line:col
│   n-1 │ context
│   n   │ the offending line
│       │     ▲── the span, underlined, with a two-word label
│   n+1 │ context
│
├ because: one sentence of cause, in the reader's vocabulary
├ counterexample: the concrete value or input that breaks (§4)
├ facts: what was known, and where each came from (§5)
╰ rule: the law this comes from, cited by ID and reachable (§7)
```

Every line after the first is optional and appears **only when it carries
information.** A diagnostic with a repair and a span and nothing else is a good
diagnostic. Padding it with constant text is worse than leaving it out, because
constant text teaches readers to skip the section that will one day matter.

**Concretely forbidden:**

- Boilerplate that is byte-identical across diagnostics. If a line does not
  depend on this program, delete it.
- Repeating the location. It appears once, in the snippet header.
- Re-rendering the source snippet for each attached note. One span, one snippet;
  additional spans get their own snippet only when they point somewhere else.
- Internal enum names, Zig/C error names, generated-file paths, and stack
  traces. A user never sees `ExpectedToken`, `/tmp/duo_x.c`, or a line number in
  the compiler's own source.
- More than one diagnostic for one cause. Cascades are suppressed (§6).

**Spans are ranges, not points.** A caret under the first character of a
construct tells a reader where to start looking; an underline under the whole
construct tells them what the compiler thinks the construct *is*, which is very
often the actual misunderstanding.

## 3. Tone

- **Second person, active, present.** "Write `s[i]`" — not "the expression
  should be" and not "one must".
- **Never blame, never praise, never apologize.** No "invalid", no "illegal",
  no "you forgot", no "oops", no "sorry". The program is a draft and the
  compiler is reading it.
- **Say what is true of the program, not what the compiler feels about it.**
  "`%` here selects the integer remainder, whose sign follows `-7`" beats
  "unexpected sign in modulo".
- **No jargon a reader cannot have met yet.** A first-week user does not know
  what a "descriptor-expected position" is. Name the thing in the source:
  "after `==`, Duo expects a case from the set `{.eof, .name, .number}`".
- **Never emit a diagnostic that only a compiler author can act on.** If the
  real problem is that a construct is unimplemented, say *that*, name the
  workaround, and cite the gap row (§9).

## 4. The counterexample block

**A refuted claim is worth much less than a refuting value.** Where the compiler
knows a concrete witness — a value, an input, a shape, a pair of dimensions —
it prints it.

```
counterexample: n = 64 reaches this shift; the width is 64
counterexample: "hello"[5] — #s is 5, so 5 is one past the end
counterexample: 256 vs 128 — the inner dimensions must match
counterexample: caller passes (1); `add` takes (a, b)
```

Three rules:

1. **The counterexample must be real, not illustrative.** It comes from the
   solver, the fact set, or the literal in the source. A made-up example that
   happens to fit is a lie with a helpful shape.
2. **The smallest one.** When the checker can minimize, it minimizes; a
   64-element counterexample teaches nothing a 2-element one does not.
3. **When there is no witness, the block is absent** — never a placeholder,
   never "some value".

This is the block that makes a fact system pay off in the user interface. A
refinement checker that can prove `n < 64` fails can almost always also produce
the `n` that makes it fail, and printing it converts an abstract refusal into an
obvious bug.

## 5. Facts and witnesses in a diagnostic

Duo's checker is three-state (Pass 106 §2 item 3): **proven / runtime-checked /
diagnostic — no silent fourth state.** A diagnostic must say which of the three
it is and, when it is the third, why the proof failed.

```
facts:  i : i64            declared at parse.duo:14
        i ≥ 0              from the loop bound at parse.duo:31
        #s = 5             from the literal at parse.duo:12
        i < #s             NOT KNOWN — nothing narrows i above
```

The last line is the whole value of the block. "Not known, and here is what
would have been enough" is the difference between a checker that argues with the
user and one that collaborates. Where a single additional fact would discharge
the obligation, the repair line says so directly: *"add `& i < #s` to the
parameter, or bind through `s:at(i)` and route the failure."*

For a **runtime-checked** outcome the same block appears as an `info`, not an
error, and only under `--info`: it is where a check was inserted and what would
erase it. That is the honest answer to "sufficiently smart compiler" — the
performance-critical reader can see every check that survived and what would
remove it.

Every fact carries **provenance** — the source location that introduced it.
A fact with no provenance is a compiler bug, not a diagnostic detail.

## 6. Severity

Four levels, and the boundary between them is about **what happens next**, not
about how bad it feels.

| level | means | exit | default |
|---|---|---|---|
| `error` | no artifact is produced | non-zero | shown |
| `warning` | an artifact is produced, and the construct is one the language is removing | 0 | shown |
| `info` | an artifact is produced; this is what the compiler decided (checks inserted, edges erased, realizations chosen) | 0 | hidden, `--info` |
| `hint` | not a level — an **attachment** to one of the above | — | with its parent |

Deliberately absent:

- **No `note`.** A note that is not attached to a diagnostic is an `info`; one
  that is attached is a `hint`.
- **No severity configuration, no `-Werror`, no per-rule suppression pragmas.**
  A warning is a construct on a removal schedule, and the schedule is the
  language's, not the project's. The set of warnings is small, finite, and
  shrinking; anything that would need permanent suppression is a design error in
  the rule.
- **No "deprecated" as a distinct level.** That is what `warning` is.

**A `warning` must name the removal**: which pass retired the construct and what
replaces it. A warning with no end date accumulates forever and is eventually
ignored, which is how every large codebase ends up with a wall of them.

## 7. Rule IDs

**Every diagnostic carries a stable ID.** The ID is the thing that survives
rewording, is searchable, is greppable in a corpus, and is what an agent keys on
(§8).

```
DUO-B4-SIGN      one boundary rule per family, one suffix per distinct check
DUO-B1-RANGE
DUO-OVFL-CONST
DUO-TEXT-UNIT
DUO-LAYOUT-DEDENT
DUO-NAME-CASE
DNB001…DNB0nn    the backend-admission family, already in use
```

Rules:

- **The ID is stable forever.** Text may be rewritten freely; an ID is never
  reused for a different check and never renamed. That is what makes it citable
  in a changelog, a lint config, or a bug report from two years ago.
- **The ID names the LAW, not the site.** Two parser paths that both enforce B-1
  emit the same ID. Two different B-1 obligations get two suffixes.
- **Every ID resolves.** `why(rule)(DUO-B4-SIGN)` prints the rule, its pass, its
  rationale, and a passing and a failing example. A diagnostic that cites a rule
  the toolchain cannot explain is a dead link.
- **Prose section references are not IDs.** "Pass 100 §1 deny table" is a fine
  thing to say in the `rule:` line *after* the ID; it is not a substitute,
  because prose section numbers move.

## 8. The machine-readable form

Per Pass 105, **the agent surface is the go-to-market**, so the machine form is
not a downgrade of the human one — it is the *same* diagnostic with more of it.

**`--diagnostics=json`**: one JSON object per diagnostic, one per line (JSONL,
so a stream can be consumed incrementally and a truncated stream is still
parseable up to the last newline), on **stdout**, with nothing else on stdout
ever.

```json
{"id":"DUO-B1-RANGE","severity":"error",
 "repair":"bind through `s:at(i)` and route the failure",
 "span":{"file":"parse.duo","line":31,"col":9,"endline":31,"endcol":13,
         "byte":812,"endbyte":816},
 "because":"nothing narrows i above; #s is 5",
 "counterexample":{"i":5,"len":5},
 "facts":[{"claim":"i >= 0","from":"parse.duo:31:5","state":"proven"},
          {"claim":"i < #s","from":null,"state":"unknown"}],
 "fixes":[{"title":"route the failure","edits":[
     {"file":"parse.duo","start":812,"end":816,"text":"s:at(i)"}]}],
 "rule":"B-1","pass":100}
```

Requirements, each of which is a thing agents and editors actually need:

- **Byte offsets alongside line/col**, and an **end** for every span. An editor
  cannot underline a range it was not given, and an agent cannot apply an edit
  to a point.
- **`fixes` are applicable**, not prose: a list of byte-range replacements that
  can be applied without re-parsing. Multiple alternatives are allowed and
  ordered by confidence; zero alternatives is legal and means the repair is
  human-only.
- **Structured facts**, each with `state ∈ {proven, unknown, runtime}` — the
  three-state outcome, machine-visible. This is the thing no other compiler's
  JSON has, and it is what lets an agent decide whether to add an annotation or
  restructure the code.
- **Progress, timing, and summary lines are not diagnostics** and never appear
  on stdout. Human progress goes to stderr.
- **The human renderer is a client of this structure**, not a parallel code
  path. If a field is not in the JSON, it cannot appear in the terminal output —
  which is the only durable way to keep the two from drifting.

**`--plain-diagnostics`** stays as the GCC-shaped line form
(`file:line:col: severity: message`) for editors and greps that want it. It is a
projection of the JSON, not a separate emitter.

**Colour is a terminal decision.** ANSI escapes are emitted only when stdout is
a TTY *and* `--no-color`/`NO_COLOR` is unset. Not "mostly"; a single unguarded
escape is what turns a machine consumer's regex into a mystery.

## 9. Unimplemented is a diagnostic kind

A compiler that is being built has a fourth thing to say, and pretending
otherwise is what produces the worst messages in this repository. Where a
construct is legal Duo that the current toolchain cannot lower:

```
error  DNB001  this shape is outside the direct backend today
  because: `{f64}` in a string hole has no direct lowering yet
  workaround: none needed — `--backend=c` handles it; it is the oracle path
  gap: gap[nn]
```

It names the construct, not an internal function. It says whether a workaround
exists. It cites the gap row, so the message and the ledger cannot drift.

**A green `duo check` on a program that cannot be built is the worst diagnostic
in the system**, because it is a confident wrong answer. Whatever `check` cannot
verify, it must say it cannot verify. Silence is a claim.

## 10. Status in this repository

Measured 2026-08-08 on `canonical-to-relation` at `0cea14c`, `zig build` clean.
Every diagnostic below was triggered and is pasted verbatim
(`--plain-diagnostics` where the snippet would otherwise be five lines of
context). The renderer is `src/term.zig`; there is no `src/diagnostics.zig`.

**The honest summary: the *good* diagnostics in this tree are very good, and
they are good because a human wrote each one by hand.** The structure around
them has no repair field, no rule ID, no counterexample block, no fact block,
no machine form beyond a text projection, and about a third of the compiler's
failures are not diagnostics at all but leaked clang errors, leaked Zig stack
traces, or silence.

### The good ones — real repairs, and they lead

```
examples/compile_fail/anchor_infix_at.duo:35:11: error: infix '@' has no meaning
  in .duo: it parsed as the matmul operator over non-tensor operands
examples/compile_fail/anchor_infix_at.duo:35:11: hint: the anchor is the GLUED
  form: close the space and 'X @ rel' becomes 'X@rel', which moves the anchor
  and retrieves. A spaced '@' is the matmul operator, and that needs both
  operands to be Tensor[..]
```

```
examples/compile_fail/pass100_goto_retired.duo:22:9: error: 'goto' is retired in
  .duo files (Pass 100 §1 deny table)
… hint: Pass 100 §13: use `break`/`continue`, or a dispatch table —
  `next(state)(event) = handler`, which gets exhaustiveness and the diagram free
… hint: Lua-shaped input is still accepted, and still lowers natively, in a
  `.lua` file
```

```
examples/compile_fail/offside_misindent.duo:12:9: error: indentation matches no
  block: this line starts at column 9, its block's statements start at column 5
… hint: blocks close by dedent; a line may only be indented further than the one
  above it when that line opened a block
```

```
examples/compile_fail/offside_end_column.duo:21:9: error: 'end' at column 9
  closes a block opened at column 5
… hint: the block already closed by dedent; align this 'end' with its opener or
  remove it
```

**Verdict: these clear the Elm/Rust bar on content and fail §1 on order.** The
`offside_misindent` message even contains a counterexample in the §4 sense
(column 9 versus column 5, both real, both from the program) — it is just spliced
into the headline prose rather than given a slot. Every one of them puts the
violation first and the repair last, so a reader who stops after the first line
knows what is wrong and not what to write. Inverting them is a formatting change,
not a redesign, and it would be the single highest-leverage day of work on this
page.

`tensor_matmul_k_mismatch` shows the same thing from the other side:

```
… warning: warning: infix '@' matmul is non-canonical; prefer explicit tensor
  APIs or typed helpers
… error: tensor matmul inner dimension mismatch: 256 vs 128
```

`256 vs 128` is exactly a §4 counterexample. Its sibling is not:

```
examples/compile_fail/tensor_broadcast_incompatible.duo:2:10: error: tensor
  broadcast incompatible shapes
```

Two shapes were compared and neither is printed. Same checker, same file, one
line apart in quality — which is what "no structure, hand-written each time"
produces.

Also note `warning: warning:` — the label is emitted twice, from the call site
and again from the renderer.

### The bad ones — every one of these is what a newcomer will actually hit

**A missing file prints a Zig error-return trace.** 20 lines, naming the user's
mise installation and four `src/main.zig` line numbers:

```
$ duo check nosuch.duo
error: FileNotFound
/Users/…/mise/installs/zig/master/lib/std/Io/Threaded.zig:4889:35: … in dirOpenFilePosix (duo)
                        .NOENT => return error.FileNotFound,
… 16 more lines …
<repo>/src/main.zig:903:9: 0x10479632b in main (duo)
```

This is a plausible first command a new user runs, and it is a stack trace.

**Constant-folding an overflow panics the compiler.** `i64max + 1` under
`--backend=direct`:

```
thread 496691 panic: integer overflow
<repo>/src/region_transform.zig:166:19: … in evalConstBinop (duo)
        .add => a + b,
```

**Clang errors leak verbatim, against a file the user never wrote.** Four
separate legal-looking Duo programs produce this class:

```
/tmp/duo_n24.c:102:5: error: use of undeclared identifier 'b1010'      ← 0b1010
/tmp/duo_n24.c:104:5: error: use of undeclared identifier '_000_000'   ← 1_000_000
/tmp/duo_n32.c:103:17: error: call to undeclared function 'e__to'      ← x:to(u8)
/tmp/duo_n37.c:105:27: error: call to undeclared function 'lua_to_num' ← s:to(i64)
/tmp/duo_n10.c:106:17: error: call to undeclared function 'lua_imod_i64'
/tmp/duo_d2.c:104:27: error: too many arguments to function call, expected 2, have 3
/tmp/duo_n40.c:6081:19: error: initializing 'lua_Value' with an expression of
                        incompatible type 'int64_t *'                 ← t:sort()
```

This is the foreign waist (Pass 103) speaking directly to the user. Every one of
them was preceded by **`✓ checked — no errors`**.

**Internal error names as user-facing text.** Every parse failure ends with a
Zig enum name: `error: parse failed: ExpectedToken`,
`error: parse failed: UnexpectedToken`. `error: FileNotFound` and
`hint: refused with: UnsupportedProgram` are the same leak. (`duo compile` and
`duo check` do print identical diagnostics — checked, they do not diverge.)

**The backend-bail diagnostic is the closest thing to §9 that exists, and it is
addressed to a compiler author:**

```
error: direct backend: DNB001: program construct is outside the direct backend subset
hint: DNB001: program is outside the current direct backend subset (machine code
      is canonical; use --backend=c only for bootstrap C emit)
hint: refused with: UnsupportedProgram
hint: bail site: lowerBinop() at dnir_lower.zig:2413 — concat
```

It has the one thing §7 asks for — a **stable ID, `DNB001`** — and it is the only
ID family in the tree. It also repeats itself three times, names a Zig function
and line, prints an internal error enum, and never says which construct in the
*user's* program was refused. (It was `print("d={d}")` with `d: f64`.)

### Silence where a diagnostic is owed

Each of these was run; each produced `✓ checked — no errors`; each then
misbehaved. These are worse than any message above.

| program | `duo check` | what happens |
|---|---|---|
| `add(1)` where `add` takes two | green | `--backend=direct` **builds and runs**, returns `6163459209` (an uninitialized register). `--backend=c` fails at clang. |
| `add(1, 2, 3)` | green | direct returns `3`; C fails at clang. |
| `"hello":notarealmethod("z")` | green | prints `nil`. No miss-repair. |
| `s:bytes()` / `s:chars()` / `s:graphemes()` | green | loop body never runs; positive control counts 6. |
| `t:sort()` on floats | green | silent no-op, input order returned. |
| `s: str = "x"` then `s[0]` | green | `--backend=c` emits `void* b0 = NULL` ⇒ SIGSEGV. |
| `7 / 0`, `7 % 0` | green | answers `0` and `7`, exit 0. |
| `0b1010`, `1_000_000` | green | clang error about an undeclared C identifier. |
| a raw `FF FE` inside a string literal | green | passes through to the binary. |
| `("x": str) .. (5: i64)` | green | `"x5"` — B-5 says this is a diagnostic. |

The arity row is the sharpest: it is the exact defect CLAUDE.md's consolidation
note describes ("duo-mcp shipped a call passing three arguments to a
two-argument function"), the fix for which was to bring the code in-tree so the
gates would catch it — and the gate does not catch it. `duo check` is green and
the direct backend produces a garbage value.

### Against §1–§9, row by row

| section | state |
|---|---|
| §1 repair-first | **NOT IMPLEMENTED.** Repairs exist and are good; they are always last. `src/term.zig` has no repair field — `locErr(loc, fmt, args)` takes a message and nothing else. |
| §2 layout | **PARTIAL.** Snippet with ±1 line of context, caret, `│` gutter: all present and well done (`printSourceContext`, `src/term.zig:274`). Fails on: location printed twice (header + `→` line); snippet re-rendered in full for every attached hint (a 3-hint diagnostic prints the same 5 lines four times); spans are **points, not ranges** — the renderer takes `loc.col` and emits one caret. |
| §2 no boilerplate | **VIOLATED, by construction.** `printDiagnosticHelp` (`src/term.zig:318`) appends two fixed strings to every error ("the marked source construct is the one Duo rejected" / "fix this diagnostic first; later messages may be caused by this one"), two more to every warning, one to every hint. They are `comptime` constants; they depend on nothing. |
| §3 tone | **MOSTLY MET.** No blame, no apology, active voice, plain vocabulary. The hand-written hints are the best writing in the repository. |
| §4 counterexample | **NO BLOCK EXISTS.** Two diagnostics carry a witness in prose (`256 vs 128`; `column 9 … column 5`); the rest carry none, and the broadcast checker discards two shapes it holds. |
| §5 facts / three-state | **DOES NOT EXIST.** No fact block, no provenance, no proven/unknown/runtime marker in any diagnostic. |
| §6 severity | **MET on the levels.** `error`/`warning`/`hint`/`info` exactly, `info` gated behind `--info`/`DUO_INFO=1`, no `note`, no `-Werror`, no suppression pragmas. Fails §6's warning rule: `@satisfies is deprecated, use @comp.satisfies instead` names a replacement but no removal schedule. And the `warning: warning:` double label. |
| §7 rule IDs | **ONE FAMILY.** `DNB001`–`DNB007`, backend-admission only, emitted as `hint:` text. Zero IDs on user-facing errors: `grep -rn 'DUO[0-9]' src/*.zig` returns **0** and `grep -rn '"E[0-9][0-9][0-9]' src/*.zig` returns **0** (positive control: `grep -rn 'DNB[0-9]' src/*.zig` returns 41). Some diagnostics cite prose sections ("Pass 100 §1 deny table", "§2 gives the anchor three stances") — good practice, not a substitute, and nothing resolves them. |
| §8 JSON | **DOES NOT EXIST.** `--diagnostics=json` is not a flag. `term.ReportStyle` has a `json` member but it is reachable only through `--test-report`/`--build-report`. |
| §8 `--plain-diagnostics` | **EXISTS AND WORKS.** `file:line:col: severity: message`, one per line, hints retained, zero ANSI escapes. `tools/lsp/src/server.duo:1372` is its consumer and parses it with `parse_diagnostics`. No byte offsets, no end positions, no fixes, no IDs — so the LSP cannot offer a code action even where the hint contains the exact replacement text. |
| §8 stdout discipline | **VIOLATED.** *Everything* goes to stderr, including diagnostics; stdout is empty. And the progress line `  > compile (f.duo) …` shares the stream with the diagnostics, so every consumer must filter it. |
| §8 colour | **VIOLATED, measurably.** `printSourceContext` emits `\x1b[2m→\x1b[0m \x1b[2m{file}:{line}:{col}\x1b[0m` **unconditionally** — not inside the `if (color)` branch that guards every other escape in the file. Measured: piping to `grep -c $'\033'` returns **2** both with and without `--no-color`. Positive control: the same grep over the rest of the output returns 0, so the counter is real. Two escaped lines survive `--no-color`, `NO_COLOR`, and a non-TTY stdout. |
| §9 unimplemented-as-a-kind | **PARTIAL.** DNB001 is the shape, addressed to the wrong reader, with no `gap[nn]` citation. |
| §9 green check on unbuildable | **THE DOMINANT FAILURE.** Ten programs in the table above. |

### The three changes that would move this page furthest

1. **Give `locErr` a repair and an ID.** Two fields on one function in
   `src/term.zig`, then reorder the renderer so the repair is the headline. The
   good messages already contain their repairs — they only need a slot.
2. **Delete `printDiagnosticHelp`.** Six constant strings, emitted on every
   diagnostic, carrying nothing. Removing them makes every existing message
   better with no writing.
3. **Make `duo check` refuse to be green when lowering will fail.** Ten of the
   silences above are one class: the checker does not model what the backends
   can build. Until it does, `check` is claiming something it has not verified,
   and CLAUDE.md §3's rule — verify by value, never by "it compiled" — applies
   to the compiler's own verdict about itself.
