# ProofUnity — unifying proof assistants with programming in Idol

Status: design. Phase 1 (kernel) implemented in `lib/proof/`, measured in
`test/proof/` against references in `test/proofdata/`.

## 1. Objective

One language for programming and proving, with less syntax than either
activity takes anywhere else:

- **Capability**: dependent types, proof terms, and tactics as ordinary Idol —
  no second language, no separate proof script dialect, no tactic metalanguage
  standing beside the programming language.
- **Unity**: a proposition is a value, a proof is a value, a tactic is a
  relation. Checking a proof is calling a relation. The same compiler, the
  same world algebra, the same evidence rules govern both.
- **Minimality**: the smallest measured proof artifact per theorem, in lines
  and in bytes, across Coq, Lean, Agda, Haskell, and Rust (§5).

This is a direction with a measured kernel, not a finished claim. §7 keeps
the honest ledger of what is new versus aspirational.

## 2. Why Idol's law already wants this

Nothing below needs a new syntactic kingdom. Each piece reduces to an
admitted concept (`law.semantic.universe`):

- **Propositions are descriptors.** `docs/spec/law.md` §8: one descriptor
  system expresses types, shapes, schemas, and protocol demands "where they
  are genuinely descriptors of existing identities." A proposition is a
  descriptor of the identity its proofs inhabit. No separate `Prop`/`Set`
  kingdom is minted beside the descriptor system.
- **Proofs are witnesses.** `law.witness.algebra`: "witness is proof of
  relation constraint satisfaction." A proof term is exactly that: the
  witness carried by the satisfaction of a proposition's demands. The
  compiler already speaks "witness"; proofs join that vocabulary instead of
  inventing `Qed`-shaped ceremony.
- **Checking is application.** `law.application.algebra`: every application
  resolves from relation × subject × operand pack × world × witnesses ×
  demand. `t:check(c, p)` — "does term `t` prove `p` under context `c`" — is
  one such application, resolved and refused like any other. An ill-typed
  proof term is a refused application, not a new error kingdom.
- **Tactics are relations on goal states.** A tactic takes a goal state and
  returns a goal state. `g:intro()`, `g:exact(u)`, `g:apply(u)` are
  subject-oriented relations (§9: `subject:edge(rest)`), the same face as
  every other Idol relation. There is no Ltac-shaped sublanguage because
  there is no need for one: tactics compose through ordinary application.
- **Names obey LAW-16.** Every new word is one irreducible lowercase word
  (`syntax.name`: `shape = .word`, `underscore = false`, `uppercase =
  false`). The kernel vocabulary is fourteen words (§3.5): no underscores,
  no capitals, no mashed compounds.
- **Delimiters keep their one meaning** (`law.md` §5). `:` orients a relation
  around its subject (`t:check(c, p)` — the term is what checking is about).
  `()` is application. Strings carry the encoded propositions; no delimiter
  is overloaded to mean "proof mode".

## 3. Phase 1 kernel: concrete syntax and semantics

Phase 1 encodes propositions and proof terms as strings and implements the
checker and a minimal tactic set as pure Idol relations over `str`/`i64`/
`bool`. The encoding is chosen for one reason: it is the whole of what the
current direct-native backend admits today (scalar precheck; see §7). The
semantics is the permanent part; the encoding is a phase-1 realization
choice and is documented as such.

### 3.1 Propositions

Prefix notation, one proposition = one self-delimiting string:

| spelling | meaning            |
|----------|--------------------|
| `a`      | atom (a–z)         |
| `>ab`    | `a` implies `b`    |
| `&ab`    | `a` and `b`        |
| `\|ab`   | `a` or `b`         |

`>a>bc` is `a → (b → c)`. A hypothesis context is propositions joined by
`;`, most recent first: `"a;>bc;>ab"`.

### 3.2 Proof terms

Natural-deduction terms, de Bruijn indices, same self-delimiting discipline:

| spelling   | rule                                        |
|------------|---------------------------------------------|
| `1`–`9`    | hypothesis (index into context)             |
| `Lx`       | implication intro (`λ`)                     |
| `Axy`      | implication elim (application)              |
| `Pxy`      | conjunction intro (pair)                     |
| `Fx`       | conjunction elim (first)                     |
| `Sx`       | conjunction elim (second)                    |
| `Ixb`      | disjunction intro left (`x : a`, other is `b`)|
| `Jxa`      | disjunction intro right (`x : b`, other is `a`)|
| `Cxyz`     | disjunction elim (case)                      |

`L` cannot be inferred — only checked — because the term does not name its
antecedent. That is a deliberate phase-1 limitation, not a gap: inference
for `L` arrives with elaboration in phase 2.

### 3.3 The checker: one relation

- `t:check(c, p)` → bool: `t` proves proposition `p` under context `c`.
  `L`-terms check against `>ab` by checking the body under `c` extended
  with `a`; every other term infers its proposition with `t:of(c)` and
  compares.
- `t:of(c)` → str: the proposition `t` proves under `c`, or `""` on any
  mismatch. Application checks the argument against the domain; `case`
  checks both branches agree. `""` is failure, never an exception: unknown
  and false stay distinct, per `law.md` §1.
- Helpers: `s:span()` (extent of the first encoded item — one scanner for
  both grammars, dispatched on the first byte), `s:first()` / `s:rest()`
  (split one item off), `c:nth(n)` (context projection), `c:push(p)`
  (context extension).

### 3.4 Tactics: hole refinement

A tactic state is a partial proof term (holes marked `?`) plus a hole list
of `context TAB proposition` entries, one string. Each tactic refines the
first hole — a graph transformation in the `law.md` §11 sense, with an
exact input occurrence (the first hole), a precondition (goal shape), and a
replacement (the plugged term):

- `p:goal()` — one hole demanding `p`.
- `g:intro()` — goal `>ab` becomes goal `b` under `c` extended with `a`;
  term grows `L?`.
- `g:exact(u)` — `u` must check against the goal; the hole becomes `u`.
- `g:apply(u)` — `u` must prove `arg → goal`; new goal `arg`; term grows
  `Au?`.
- `g:split()` — goal `&ab` becomes goals `a`, `b`; term grows `P??`.
- `g:left()` / `g:right()` — goal `|ab` becomes goal `a` / `b`.
- `g:qed()` — returns the term iff no holes remain, else `""`.

Every tactic fails closed (`""`) on a wrongly shaped goal. And `qed` does
not trust tactic bookkeeping: the finished term is re-run through `check`
(`law.run.algebra`: transport completion never proves inner success).

### 3.5 Worked example

Composition `(a→b) → ((b→c) → (a→c))`, proposition `>>ab>>bc>ac`:

Term face (3 lines):

```id
p = ">>ab>>bc>ac"
t = "LLLA2A31"
ok = t:check("", p)
```

Tactic face (10 lines):

```id
g = ">>ab>>bc>ac":goal()
g = g:intro()
g = g:intro()
g = g:intro()
g = g:apply("2")
g = g:apply("3")
g = g:exact("1")
t = g:qed()
ok = t:check("", ">>ab>>bc>ac")
```

Kernel vocabulary census (22 words, all LAW-16 clean): `span`, `first`,
`rest`, `nth`, `push`, `of`, `check`, `term`, `holes`, `ctx`, `prop`,
`head`, `tail`, `plug`, `goal`, `intro`, `exact`, `apply`, `split`,
`left`, `right`, `qed`. (Each resolves to an
admitted binding — the binding census `law.binding.census` holds by
construction: there is nowhere else for a name to resolve.)

## 4. Proofs and the §67 world/projection algebra

`docs/spec/constitution.md` §67 is the sole authority for home, subject,
world, protocol, witness, injection, projection, union, reachability,
shell/run/outcome, binding census, and completion metrics. Proofs compose
with it as follows — no new algebra is introduced:

- **Hypotheses are injected worlds.** `intro` derives a new closed world
  carrying exactly one more fact (`law.projection.algebra`: injection
  derives a new world; "nested injection shadows by formation order not
  search"). De Bruijn indices *are* formation-order addressing: index 1 is
  the most recently injected hypothesis. The checker evaluates the term
  under the injected world and never mutates the caller's world —
  interjection semantics (`thing@{…}`), not ambient capture
  (`law.injection.authority`: a closure captures the smallest exact
  necessary facts).
- **Checking is world-scoped evaluation.** `t:check(c, p)` runs under the
  world `c`. A hypothesis absent from `c` is absent from that world, not a
  special diagnostic — exactly the `law.md` §6 reading of stage/world
  absence.
- **Tactics are transformations** (`law.md` §11): exact input occurrence
  ids (first-hole position), preconditions (goal shape), world obligations
  (the extended context), replacement ids (the plugged term), and a
  verification witness (the final `check`). Nothing is destructively
  rewritten; partial terms are values threaded through.
- **Scripts are runs; outcomes are checked** (`law.shell.run`,
  `law.run.algebra`). A tactic script is a `run`; its outcome is either a
  checked proof term or a refusal. Refusal is total: a tactic applied to a
  wrongly shaped goal yields `""`, and `qed` on open holes yields `""`.
- **Witnesses stay witnesses** (`law.witness.algebra`). A proof term is
  evidence of proposition satisfaction, not a runtime object the program
  must carry: after `check` succeeds, the term may be erased. Proof
  erasure is phase 5; the law already permits it ("materialize witness
  data only when reflection or runtime uncertainty is demanded").
- **Completion metrics are the admission evidence** (`law.completion.metric`).
  The minimal-syntax claim is not prose: `test/proof/main.id` is a machine
  census that counts non-blank lines and bytes of the Idol proof artifact
  against the Coq, Lean, and Agda artifacts in `test/proofdata/` and
  refuses unless Idol is strictly smaller on both measures.

## 5. Comparison: the same theorems everywhere

Two theorems: identity (`A → A`) and composition
(`(A→B) → ((B→C) → (A→C))`). Non-blank lines / bytes of the complete
runnable artifact in each language. Haskell and Rust rows are
Curry–Howard programs — the function *is* the proof — which is precisely
the unity this design claims: in Idol the same artifact is both.

| language | identity | composition | two-theorem file |
|----------|----------|-------------|------------------|
| Coq      | 5 / 79   | 8 / 141     | 13 / 221         |
| Lean 4   | 1 / 55   | 2 / 105     | 3 / 161          |
| Agda     | 2 / 46   | 2 / 90      | 4 / 137          |
| Haskell  | 2 / 24   | 2 / 60      | —                |
| Rust     | 3 / 31   | 3 / 101     | —                |
| Idol     | 1 / 26   | 1 / 40      | 2 / 66           |

Idol artifacts measured:

```id
a = "L1":check("", ">aa")
b = "LLLA2A31":check("", ">>ab>>bc>ac")
```

Read honestly: Lean ties Idol on identity lines (1 each); Haskell's
identity program is 2 bytes shorter than Idol's (24 vs 26). Everywhere
else — both theorems, both measures, and the whole file the test
censuses — Idol is strictly smallest. The proof term itself (`L1`,
`LLLA2A31`) is the smallest proof object in any row: there is no
`intros`/`exact`/`Qed` ceremony because there is no separate proof
language to address.

Reference artifacts live in `test/proofdata/` (`id.v`, `id.lean`,
`id.agda`, `id.id`); the census runs in `test/proof/main.id`.

## 6. Phased implementation plan

- **Phase 1 — kernel (done).** String-encoded propositions, proof terms,
  `check`/`of`, hole-refinement tactic set. Files: `lib/proof/prop.id`
  (scanner), `lib/proof/check.id` (checker), `lib/proof/tac.id`
  (tactics). Tests: `test/proof/main.id` proves identity and composition
  by term and by tactic, checks refusals fail closed, and censuses
  line/byte counts against `test/proofdata/`. All Idol code: zero
  comments, no underscores, LAW-16 names, `subject:edge(rest)`.
- **Phase 2 — descriptor-native propositions.** Replace the string
  encoding with packs (`{k = "imp", l = a, r = b}`) once the native
  backend admits pack-typed parameters; add an elaborator from a terse
  surface syntax to kernel terms. No compiler changes: it is a library
  phase, gated only on backend subset admission.
- **Phase 3 — dependent types.** `A`/`E` binders (de Bruijn stays),
  equality, induction principles. Propositions become dependent
  descriptors under `law.md` §8.
- **Phase 4 — automation.** Tactic combinators (`;` sequencing, `try`,
  `repeat`), assumption search, congruence closure — still ordinary
  relations, still fail-closed.
- **Phase 5 — extraction and erasure.** Programs with proofs erase to
  programs; `law.witness.algebra` governs when witness data materializes.
  Proof-carrying compilation: the compiler may demand a proof term as the
  witness for an optimization's precondition.
- **Phase 6 — compiler integration.** Proof terms as graph witnesses;
  `check` as a world-scoped relation inside the compiler's own
  reasoning. Explicitly *not* a change to `lib/compiler/native.id`'s
  codegen: integration is through witness facts, and each step needs its
  own evidence.

## 7. Honesty ledger

Genuinely new: a proof kernel in which propositions, proof terms, and
tactics are ordinary Idol values and relations — no proof sublanguage —
with world-algebra semantics for hypotheses (injection, formation-order
addressing) and a machine-checked minimal-syntax census against
Coq/Lean/Agda.

Aspirational: dependent types (§6 phase 3+), tactic automation (phase 4),
extraction (phase 5), compiler integration (phase 6), and the headline
"more capable than all other languages combined," which names the
direction and its mechanism (one kernel for programming and proving),
not the current state.

Load-bearing constraint, stated plainly: phase 1 is string-encoded
because the direct-native backend's scalar precheck currently refuses
`any`-typed pack projection through function parameters. The encoding
is a realization choice under `law.md` §12, not a semantic commitment;
phase 2 removes it without touching the checker rules.

## 8. Integration hooks (no compiler changes)

- `lib/compiler/native.id` and siblings: untouched. The kernel is a
  library under `lib/proof/`; composition today is source-partition
  concatenation (`cat lib/proof/*.id test/proof/main.id`), which is the
  honest current mechanism given no import system (`law.md` §7).
- Run: `idol run --backend direct <unit>` from the repo root (proofdata
  paths are relative).
- Future hook, no action now: when the backend admits richer values, the
  kernel's relations keep their names and faces; only the encoding
  changes. A world-scoped `check` (`t:check(c, p)@logic`) is the
  sketched phase-6 spelling, not a current directive.
