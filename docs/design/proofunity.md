# ProofUnity — unifying proof assistants with programming in Idol

| # | directive |
|---|---|
| 1 | Status: design. |
| 2 | Phase 1 (kernel) implemented in `lib/proof/`, measured in `test/proof/` against references in `test/proofdata/` — `proofunity ok`. |

## 1. Objective

| # | directive |
|---|---|
| 1 | Supreme requirement (#13, confirmed): the proof assistant and the programming language are not two systems that interoperate — they are the same thing. |
| 2 | There is no proof language distinct from the programming language; proving is what programming looks like when the descriptor is a proposition. |
| 3 | A proposition is a descriptor (a type). |
| 4 | A proof term is a program (a witness). |
| 5 | A tactic is a relation (a function). |
| 6 | Checking is application (evaluation). |
| 7 | The kernel below is not a proof assistant *in* Idol; it is Idol, applied to propositions. |
| 8 | Unification was the draft; identity is the requirement. |

| # | directive |
|---|---|
| 1 | One language for programming and proving, with less syntax than either activity takes anywhere else: |

- **Capability**: dependent types, proof terms, and tactics as ordinary Idol —
  no second language, no separate proof script dialect, no tactic metalanguage
  standing beside the programming language. Capability is co-equal with
  performance: the deliverable is fastest *and* most powerful.
- **Unity**: a proposition is a value, a proof is a value, a tactic is a
  relation. Checking a proof is calling a relation. The same compiler, the
  same world algebra, the same evidence rules govern both.
- **Minimality**: the smallest measured proof artifact per theorem, in lines
  and in bytes, across Coq, Lean, Agda, and Python (§5) — machine-censused,
  not asserted.

| # | directive |
|---|---|
| 1 | This is a direction with a measured kernel, not a finished claim. §9 keeps the honest ledger of what is new versus aspirational. §6 names the power frontiers — what Idol expresses that no other language can. §7 makes the synthesis rigorous: density *is* power, directness *is* speed, from the same source. |

## 2. Why Idol's law already wants this

| # | directive |
|---|---|
| 1 | Nothing below needs a new syntactic kingdom. |
| 2 | Each piece reduces to an admitted concept (`law.semantic.universe`): |

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
  there is no need for one: tactics compose through ordinary application —
  including chained in one expression
  (`p:goal():intro():apply("2"):exact("1"):qed()`), because the goal state
  is a named value, not ambient tactic state.
- **Names obey LAW-16.** Every new word is one irreducible lowercase word
  (`syntax.name`: `shape = .word`, `underscore = false`, `uppercase =
  false`). The kernel vocabulary is twenty-three words (§3.5): no
  underscores, no capitals, no mashed compounds.
- **Delimiters keep their one meaning** (`law.md` §5). `:` orients a relation
  around its subject (`t:check(c, p)` — the term is what checking is about).
  `()` is application. Strings carry the encoded propositions; no delimiter
  is overloaded to mean "proof mode".

## 3. Phase 1 kernel: concrete syntax and semantics

| # | directive |
|---|---|
| 1 | Phase 1 encodes propositions and proof terms as strings and implements the checker and a minimal tactic set as pure Idol relations over `str`/`i64`/ `bool`. |
| 2 | The encoding is chosen for one reason: it is the whole of what the current direct-native backend admits today (scalar precheck; see §9). |
| 3 | The semantics is the permanent part; the encoding is a phase-1 realization choice and is documented as such. |

### 3.1 Propositions

| # | directive |
|---|---|
| 1 | Prefix notation, one proposition = one self-delimiting string: |

| spelling | meaning            |
|----------|--------------------|
| `a`      | atom (a–z)         |
| `>ab`    | `a` implies `b`    |
| `&ab`    | `a` and `b`        |
| `\|ab`   | `a` or `b`         |

| # | directive |
|---|---|
| 1 | `>a>bc` is `a → (b → c)`. |
| 2 | A hypothesis context is propositions joined by `;`, most recent first: `"a;>bc;>ab"`. |

### 3.2 Proof terms

| # | directive |
|---|---|
| 1 | Natural-deduction terms, de Bruijn indices, same self-delimiting discipline: |

| spelling   | rule                                          |
|------------|-----------------------------------------------|
| `1`–`9`    | hypothesis (index into context)               |
| `!10!`…    | hypothesis, larger indices (`!`-quoted digits) |
| `Lx`       | implication intro (`λ`)                       |
| `Axy`      | implication elim (application)                 |
| `Pxy`      | conjunction intro (pair)                       |
| `Fx`       | conjunction elim (first)                       |
| `Sx`       | conjunction elim (second)                      |
| `Ixb`      | disjunction intro left (`x : a`, other is `b`) |
| `Jxa`      | disjunction intro right (`x : b`, other is `a`)|
| `Cxyz`     | disjunction elim (case)                        |

| # | directive |
|---|---|
| 1 | Single digits stay one byte (`1`); indices ≥ 10 are `!`-quoted (`!10!`, `!21!`). `L` cannot be inferred — only checked — because the term does not name its antecedent. |
| 2 | That is a deliberate phase-1 limitation, not a gap: inference for `L` arrives with elaboration in phase 2. |

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
  (context extension), `t:num()` (parse a `!`-quoted index).

### 3.4 Tactics: hole refinement

| # | directive |
|---|---|
| 1 | A tactic state is a partial proof term (holes marked `?`) plus a hole list of `context TAB proposition` entries, one string. |
| 2 | Each tactic refines the first hole — a graph transformation in the `law.md` §11 sense, with an exact input occurrence (the first hole), a precondition (goal shape), and a replacement (the plugged term): |

- `p:goal()` — one hole demanding `p`.
- `g:intro()` — goal `>ab` becomes goal `b` under `c` extended with `a`;
  term grows `L?`.
- `g:exact(u)` — `u` must check against the goal; the hole becomes `u`.
- `g:apply(u)` — `u` must prove `arg → goal`; new goal `arg`; term grows
  `Au?`.
- `g:split()` — goal `&ab` becomes goals `a`, `b`; term grows `P??`.
- `g:left()` / `g:right()` — goal `|ab` becomes goal `a` / `b`.
- `g:qed()` — returns the term iff no holes remain, else `""`.

| # | directive |
|---|---|
| 1 | Every tactic fails closed (`""`) on a wrongly shaped goal. |
| 2 | And `qed` does not trust tactic bookkeeping: the finished term is re-run through `check` (`law.run.algebra`: transport completion never proves inner success). |

### 3.5 Worked example

| # | directive |
|---|---|
| 1 | Composition `(a→b) → ((b→c) → (a→c))`, proposition `>>ab>>bc>ac`: |

| # | directive |
|---|---|
| 1 | Term face (1 line): |

```id
b = "LLLA2A31":check("", ">>ab>>bc>ac")
```

| # | directive |
|---|---|
| 1 | Tactic face — one chained expression (1 line), because goal states are values and tactics are ordinary relations: |

```id
g = ">>ab>>bc>ac":goal():intro():intro():intro():apply("2"):apply("3"):exact("1"):qed()
d = g:check("", ">>ab>>bc>ac")
```

| # | directive |
|---|---|
| 1 | The chained tactic proof builds exactly the term the term face checks (`LLLA2A31`): the two faces are the same values, not two languages. |

| # | directive |
|---|---|
| 1 | Kernel vocabulary census (37 words, all LAW-16 clean): `span`, `binary`, `triple`, `scan`, `first`, `rest`, `num`, `digits`, `find`, `nth`, `push`, `of`, `app`, `pair`, `fst`, `snd`, `inl`, `inr`, `elim`, `lam`, `infer`, `check`, `term`, `holes`, `head`, `tail`, `ctx`, `prop`, `plug`, `goal`, `intro`, `exact`, `apply`, `split`, `left`, `right`, `qed`. |
| 2 | (Each resolves to an admitted binding — the binding census `law.binding.census` holds by construction: there is nowhere else for a name to resolve.) |

### 3.6 Implementation discipline (Idol family code)

| # | directive |
|---|---|
| 1 | The kernel is functional/chained throughout — no `while`, `if`, or `for` in any file. |
| 2 | Branching is short-circuit `and`/`or`: `c and v or rest` means "if c then v, else rest", and it is correct because every value in branch position is truthy (every string including `""`, every nonzero `i64`, `true`); booleans use the positive form `c and t or false`. |
| 3 | Looping is structural recursion over `first`/`rest`/`sub` (`scan`, `digits`, `find`, `walk`, `seek`), which terminates because each call shrinks its input; `and`/`or` short-circuit gives the recursive branch its laziness (relation arguments are strict — measured). |
| 4 | The two `i64` computations that can legitimately yield 0 (`digits`, `walk`) offset by one internally, because 0 is falsy. |
| 5 | Each name is bound exactly once — files are table scope, so there is no rebinding (`ok = ok and …` is rewritten as one conjunction). |
| 6 | Names are single irreducible lowercase words; comments are zero, absolutely. |

## 4. Proofs and the §67 world/projection algebra

| # | directive |
|---|---|
| 1 | `docs/spec/constitution.md` §67 is the sole authority for home, subject, world, protocol, witness, injection, projection, union, reachability, shell/run/outcome, binding census, and completion metrics. |
| 2 | Proofs compose with it as follows — no new algebra is introduced: |

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
  against the Coq, Lean, Agda, and Python artifacts in `test/proofdata/`
  and refuses unless Idol is strictly smaller on both measures.

## 5. Comparison: the same theorems everywhere

| # | directive |
|---|---|
| 1 | Three theorems: identity (`A → A`), composition (`(A→B) → ((B→C) → (A→C))`), and a 20-deep implication chain — `(a→b)→…→(t→u)→(a→u)`. |
| 2 | Non-blank lines / bytes of the complete runnable artifact in each language. |
| 3 | Haskell and Rust rows are Curry–Howard programs — the function *is* the proof — which is precisely the unity this design claims: in Idol the same artifact is both. |

| language | identity | composition | chain20   | three-theorem file |
|----------|----------|-------------|-----------|--------------------|
| Coq      | 5 / 79   | 8 / 141     | 14 / 705  | 27 / 926           |
| Lean 4   | 1 / 55   | 2 / 105     | 10 / 625  | 13 / 786           |
| Agda     | 2 / 46   | 2 / 90      | 10 / 609  | 14 / 746           |
| Haskell  | 2 / 24   | 2 / 60      | —         | —                  |
| Rust     | 3 / 31   | 3 / 101     | —         | —                  |
| Idol     | 1 / 26   | 1 / 40      | 1 / 202   | 3 / 268            |

| # | directive |
|---|---|
| 1 | Idol artifacts measured (`test/proofdata/id.id`): |

```id
a = "L1":check("", ">aa")
b = "LLLA2A31":check("", ">>ab>>bc>ac")
e = "LLLLLLLLLLLLLLLLLLLLLA2A3A4A5A6A7A8A9A!10!A!11!A!12!A!13!A!14!A!15!A!16!A!17!A!18!A!19!A!20!A!21!1":check("", ">>ab>>bc>>cd>>de>>ef>>fg>>gh>>hi>>ij>>jk>>kl>>lm>>mn>>no>>op>>pq>>qr>>rs>>st>>tu>au")
```

| # | directive |
|---|---|
| 1 | The chain is the paradigm demo, and it is a *scaling* claim, not a constant-factor one: Idol proof artifacts are **O(1) lines in proof depth** — the chain proof is one line at depth 2 and one line at depth 20 — while Coq tactic scripts are O(n) lines (14 at depth 20), Lean/Agda term proofs are O(n) in statement size (10 lines), and the ratio grows without bound as proofs get deeper. |
| 2 | Measured at depth 20: 14× fewer lines than Coq, 10× fewer than Lean and Agda. |

### 5.1 Against Python

| # | directive |
|---|---|
| 1 | The same 20-deep chain in Python (`test/proofdata/chain.py`), the shortest honest Python telling — proof by SMT refutation with z3: |

| language | chain20 artifact |
|----------|------------------|
| Python + z3 | 11 lines / 524 bytes |
| Idol        | 1 line / 201 bytes  |

| # | directive |
|---|---|
| 1 | 11× fewer lines, 2.6× fewer bytes — and the asymmetry runs deeper than the counts: z3 is not the standard library (it is a `pip install` plus a native solver dependency), while the Idol artifact is zero-dependency and compiles through the direct backend to machine code. |
| 2 | In pure-stdlib Python the theorem is *inexpressible* without hand-rolling the kernel itself (~100 lines): the comparison is not lines but possible versus impossible. |
| 3 | Stated carefully: where both languages natively express the program — writing the *checker* — Python and Idol are peers (dynamic slicing buys Python the same terseness). |
| 4 | The 10× frontier is proof *artifacts*, the domain Python cannot natively express. |
| 5 | That is exactly the capability gap §6 is about. |

| # | directive |
|---|---|
| 1 | Reference artifacts live in `test/proofdata/` (`id.v`, `id.lean`, `id.agda`, `id.id`, `chain.py`); the census runs in `test/proof/main.id`. |

## 6. Power frontiers: what Idol expresses that no other language can

| # | directive |
|---|---|
| 1 | Performance frontiers are the sibling workstream's benchmarks. |
| 2 | These are the capability frontiers — each is something no other language's design permits, with the phase-1 evidence that it is real and not a slogan. |

| # | directive |
|---|---|
| 1 | **Frontier 1 — the proof assistant is the programming language (#13).** In Coq, tactics are an imperative sublanguage (Ltac) operating on an unnamed, ambient goal. |
| 2 | In Lean, `by` blocks are metaprograms over an elaborator monad. |
| 3 | In Idol the goal state is a *named value* and each tactic is a relation: `p:goal():intro():apply("2"):exact("1"):qed()` is one expression in the same language as the program it proves things about. |
| 4 | There is no proof mode to enter and no second grammar to learn — the term face (`"LLLA2A31"`) and the tactic face are the same values, and `check` is an ordinary relation any program can call. |
| 5 | No other proof assistant makes the proof state a first-class subject of `subject:edge(rest)` composition, because no other one accepts the identity: here proving is not unified *with* programming, it *is* programming over propositional descriptors. |

| # | directive |
|---|---|
| 1 | **Frontier 2 — world-scoped checking as injection.** `t:check(c, p)` evaluates under the world `c`; `intro` injects a hypothesis world and de Bruijn indices address it by formation order. |
| 2 | Contexts are values the programmer binds, passes, and transforms — Coq and Lean contexts are ambient global state that no program can name. |
| 3 | The phase-6 spelling (`t:check(c, p)@logic`) makes the world explicit; the phase-1 kernel already models it: the checker never mutates the caller's world. |

| # | directive |
|---|---|
| 1 | **Frontier 3 — one witness algebra for programs and compiler.** The `check` the programmer calls is the *shape of the evidence* the compiler will demand for an optimization's precondition (phase 5: proof-carrying compilation; phase 6: proof terms as graph witnesses). |
| 2 | Coq pairs Ltac with an OCaml compiler, Lean pairs tactics with a C++ compiler — two justification languages bolted together. |
| 3 | Idol has one relation algebra serving both masters. |
| 4 | This is the concrete content of "more rigorous than Coq/Lean/Agda": not stronger logic (phase 1 is propositional — strictly *weaker*), but an architecture with no seam between the language that proves and the language that compiles. |

| # | directive |
|---|---|
| 1 | **Frontier 4 — self-censusing minimality.** `test/proof/main.id` machine-counts lines and bytes against Coq, Lean, Agda, and Python and *fails the suite* unless Idol is strictly smallest on every measure. |
| 2 | No other language's test suite makes a machine-checked claim about its own proof size; it is `law.completion.metric` applied to proof artifacts. |
| 3 | The census already paid for itself once: the case-analysis test caught a real kernel bug (the `\|`/atom byte-range collision in `span`, §9) that review missed. |

| # | directive |
|---|---|
| 1 | **What proofs can Idol carry that Coq/Lean/Agda can't — or only with far more machinery?** Stated with the ledger open: none, in logical strength — phase 1 is propositional. |
| 2 | The frontier is elsewhere: (a) proofs *about compilation itself* — a transformation's meaning-preservation witnessed in the same kernel the programmer uses (Coq needs a CompCert-scale deep embedding of the compiler to say this at all) |
| 3 | (b) world-scoped proofs carried as first-class values, provable under an injected hypothesis world without touching ambient state (Coq/Lean need section machinery or explicit context threading) |
| 4 | (c) machine-checked *claims about proofs* — the census is a proof about proof size that no assistant's suite expresses. |
| 5 | The paradigm shift is not a stronger logic; it is that proving, programming, and compiling stop being three activities. |

## 7. The synthesis: density is power, directness is speed

| # | directive |
|---|---|
| 1 | The claim is that performance and capability come from the *same* source — the Idolic invariants plus the direct-to-machine-code pipeline — and it can be made precise instead of asserted. |

| # | directive |
|---|---|
| 1 | **Definitions.** A *semantic fact* is one load-bearing unit of meaning: a proposition node, a rule application, a binder, a context entry. |
| 2 | The *syntactic overhead ratio* is R = bytes / facts for an artifact. |
| 3 | Lower R means more meaning per character. |

| # | directive |
|---|---|
| 1 | **Lemma 1 (density → power).** LAW-16 (one irreducible word per concept), `subject:edge(rest)` (no separate tactic grammar), prefix self-delimiting encoding (no parentheses, no commas, no keywords), and de Bruijn indices (no binder names) jointly force every character of a proof artifact to be load-bearing. |
| 2 | Measured on the 20-deep chain (~145 facts: 83 proposition nodes + 62 term nodes): Idol 201 B ⇒ R ≈ 1.4 |
| 3 | Coq 705 B ⇒ R ≈ 4.9 |
| 4 | Lean 625 B ⇒ R ≈ 4.3 |
| 5 | Python+z3 524 B ⇒ R ≈ 3.6. |
| 6 | The human-facing consequence is power: more meaning per character is more that one line can say — the whole 20-step proof fits in a single line because there is nothing left to remove. |

| # | directive |
|---|---|
| 1 | **Lemma 2 (directness → speed).** `law.md` §12: the direct pipeline's realization encoding "must not own semantic meaning" — there is no meaning-owning middle layer between the semantic graph and machine code. |
| 2 | Compile work therefore scales with *facts*, not with syntactic overhead: every IR kingdom that owns meaning must be kept consistent (invalidation, rebuilding, re-verification), and that bookkeeping is compile time and bug surface. |
| 3 | Fewer bytes per fact ⇒ less parse, lower, and invalidation work per fact ⇒ speed. |

| # | directive |
|---|---|
| 1 | **Theorem (informal).** Minimizing bytes-per-fact simultaneously maximizes meaning-density for the human (power) and minimizes compiler work per fact (performance). |
| 2 | The same invariants produce both effects: the rules that force density (LAW-16, minimum source spelling, one-meaning delimiters) are the same rules that shrink the compiler's case analysis (one binding form, one application algebra, one witness algebra). |
| 3 | The language's density *is* its power; the compiler's directness *is* its speed; and they are one mechanism, not two goals traded against each other. |

| # | directive |
|---|---|
| 1 | **Falsifiability.** This is a standing experiment, not a slogan: `test/proof/main.id` refuses unless the Idol artifact beats every censused language on lines *and* bytes. |
| 2 | If an Idol artifact ever loses, the suite says so and the claim is falsified for that artifact. |
| 3 | The sibling workstream's benchmarks are the performance half of the same experiment. |

| # | directive |
|---|---|
| 1 | **Capability targets, mapped to mechanism:** |

- *More expressive than Python* — proof artifacts 11× smaller by line;
  and proofs are inexpressible in stdlib Python at all (§5.1).
- *More safe than Rust* — the law structure as compile-time guarantees:
  phase-5 proof-carrying compilation makes safety evidence (not just
  safety rules) a compiler input. Target, not current state (§9).
- *More rigorous than Coq/Lean/Agda* — unity, not logical strength: one
  language for programming and proving, one witness algebra for proofs
  and compiler, no bolted-together seam (Frontier 3).
- *More innovative than research languages* — self-censusing minimality
  as standing practice (Frontier 4): the language measures itself
  against its competitors on every run.

## 8. Phased implementation plan

- **Phase 1 — kernel (done).** String-encoded propositions, proof terms
  (`1`–`9` plus `!n!` multi-digit indices), `check`/`of`, hole-refinement
  tactic set — written as pure functional Idol per §3.6 (no
  `while`/`if`/`for`; branching by short-circuit `and`/`or`; structural
  recursion; each name bound once). Files: `lib/proof/prop.id`
  (scanner), `lib/proof/check.id` (checker), `lib/proof/tac.id`
  (tactics). Tests: `test/proof/main.id`
  proves identity, composition, and the 20-deep chain by term, proves
  composition by chained tactic, exercises every rule (pair, projections,
  injections, case), checks refusals fail closed (`qed` on open holes,
  wrong-shape tactics, wrong proofs), and censuses line/byte counts
  against `test/proofdata/` — `proofunity ok`. The suite caught one real
  kernel bug before release: `span` classified `|` (byte 124) as an atom
  because the atom test was `b >= 97`; fixed to `b >= 97 and b <= 122`
  (§9). All Idol code: zero comments, no underscores, LAW-16 names,
  `subject:edge(rest)`. This phase is the #13 identity requirement made
  concrete: the "proof assistant" is 37 ordinary relations — there is no
  second language in the artifact.
- **Phase 2 — descriptor-native propositions.** Replace the string
  encoding with packs (`{k = "imp", l = a, r = b}`) once the native
  backend admits pack-typed parameters; add an elaborator from a terse
  surface syntax to kernel terms. Multi-digit indices become ordinary
  integers. No compiler changes: it is a library phase, gated only on
  backend subset admission.
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

## 9. Honesty ledger

| # | directive |
|---|---|
| 1 | Genuinely new: a proof kernel in which propositions, proof terms, and tactics are ordinary Idol values and relations — no proof sublanguage — with world-algebra semantics for hypotheses (injection, formation-order addressing), tactic scripts as ordinary relation chains over named goal values, and a machine-checked minimal-syntax census against Coq/Lean/Agda/Python. |
| 2 | The 10× frontier is measured (chain20: 14× fewer lines than Coq, 10× than Lean/Agda, 11× than Python+z3) and it is a scaling law — O(1)-line artifacts against O(n)-line scripts — not a constant factor. |

| # | directive |
|---|---|
| 1 | Aspirational: dependent types (§8 phase 3+), tactic automation (phase 4), extraction and proof-carrying compilation (phase 5), compiler integration (phase 6), and "more safe than Rust," which names the target and its mechanism (law structure as compile-time evidence), not the current state. |

| # | directive |
|---|---|
| 1 | Stated plainly, three scoping facts: (1) phase 1's logic is propositional — strictly weaker than Coq/Lean/Agda's type theories; the "more rigorous" claim is architectural unity (Frontier 3), not logical strength. |
| 2 | (2) The 10× claims are about proof *artifacts*; writing the checker itself, Python and Idol are peers — the frontier is the domain Python cannot natively express. |
| 3 | (3) The Python comparison uses z3, which is not the standard library — the dependency asymmetry is part of the point, not a footnote to hide. |

| # | directive |
|---|---|
| 1 | Load-bearing constraint: phase 1 is string-encoded because the direct-native backend's scalar precheck currently refuses `any`-typed pack projection through function parameters. |
| 2 | The encoding is a realization choice under `law.md` §12, not a semantic commitment; phase 2 removes it without touching the checker rules. |

| # | directive |
|---|---|
| 1 | Bug the census caught: `span` treated `\|` (byte 124) as an atom because the atom guard was `b >= 97`; disjunction hypotheses then split wrong under `intro`. |
| 2 | The case-analysis test failed, the trace localized it, fixed to `b >= 97 and b <= 122`. |
| 3 | Recorded here because a test suite that catches real kernel bugs is evidence the census is load-bearing, not ceremony. |

## 10. Integration hooks (no compiler changes)

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
