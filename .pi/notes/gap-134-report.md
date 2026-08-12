# GAP-134 report — one generatable grammar authority

Analysis by the grammar-authority lane. **Not Idol authority.** This is a
design + status report produced from reading AGENTS.md, C0, GAP-134, GAP-145,
docs/spec/grammar.md, the current token/grammar projections, the Tree-sitter
emitter, and the live claims. It is the deliverable the goal's "Stop / Report"
section asks for. It does not implement the parser slice and does not edit any
authority file (no claim acquired; upstream blockers open).

Tree: `clpi/duo` @ HEAD `a44a088`, dirty (concurrent lanes active).

## 0. Verified current state

- C0 (`docs/spec/constitution.md`) is **structured law notation, non-source**,
  retained while GAP-145 closes (C0 preamble). §5 syntax, §6 semantic roles,
  §33 self-hosting (slice 2 "must consume the GENERATED constitutional
  grammar"). §33 invariant: old = oracle, new = candidate, differential =
  judge.
- `docs/spec/grammar.md` is **authored prose**, explicitly "not a second
  grammar authority and must not be used to hand-build parser tables"; it
  defers all machine-readability to GAP-134.
- Token identities `lib/std/compiler/token.id`: partial GAP-145 work present
  (`KIND_TEXT_LIT`/`BYTES_LIT`/`COMPAT_TEXT_LIT`/`COMPAT_LONG_TEXT_LIT` =
  105–108) **alongside** the collapsed legacy `KIND_STRING_LIT = 3`. **No
  grammar-role projection at all.**
- Generation pattern already exists and is the right shape:
  `src/token_semantic.zig` (host keyword facts) → `src/token_classify_gen.zig`
  (generator) → `lib/std/token/classify.id` (generated projection, 54 keywords,
  3 category bitsets). It classifies **keywords only**; it emits **no** roles.
- `src/token_semantic.zig` carries **no** precedence/associativity/prefix/
  postfix/expr-start/param-slot/body-start facts (confirmed by grep).
- `src/parser.zig:scan_func_header_signal` (line 2542) is the host decision
  GAP-134 names as next-to-transfer; line 2529 confirms it uses mutable
  save/scan/restore. Moving it verbatim is a rejected fourth authority.
- `scripts/treesitter_emit.id` honestly carries an **authored residue**
  (counted, GAP-049) and emits from registries, not from a normative EBNF; it
  refuses to project grammar.md §3 over the tracked corpus (a language
  decision, not a build one).

## 1. Canonical machine-readable grammar owner (where it must live)

**One new canonical Idol source module** that states grammar-recognition facts
as admitted structured values — the machine-readable form of the grammar law
C0 already owns. It is the **first** machine-readable grammar authority, not a
second ontology (recognition/provenance facts are explicitly "syntax provenance
after resolution" per grammar.md, not semantic identity).

- Owner path (proposed): `lib/std/compiler/grammar.id` — one concept per file
  (the grammar authority). Consumes token **identities** from
  `lib/std/compiler/token.id` (Devin's boundary) as inputs. Never reads
  spelling.
- Constitutional hook: C0 line 3037 — *"grammar supplies orientation
  precedence and provenance"*; line 2999 — *"operator -> ordinary relation
  identity plus orientation and precedence provenance"*. So precedence and
  associativity are lawfully **grammar provenance**, owned here, not semantic
  identity and not a host registry.
- Generator (transitional host bridge, same shape as
  `token_classify_gen.zig`): reads `grammar.id` facts, emits (a) the human
  `docs/spec/grammar.md` projection (**generated**, replacing authored prose +
  ellipses) and (b) compact role tables `lib/std/compiler/grammar/roles.id`.
  The **facts** live in `.id`; the Zig file is only the emitter (a generator,
  not a registry — admissible under the monoglot boundary as the smallest
  bridge to its Idol replacement).
- All consumers (parser, `scripts/treesitter_emit.id`, formatter,
  canonicalizer, LSP, MCP) read generated `roles.id` + token identities.

This satisfies "do not create another handwritten Markdown grammar / parser-
local role tables / a new Zig grammar registry / another legacy syntax list /
a second semantic grammar ontology."

## 2. Generated projections

```
C0 (law)  ──►  lib/std/compiler/grammar.id   (canonical machine-readable owner)
                     │ consumes token identities (GAP-145 boundary)
                     ▼
               grammar_role_gen  (host generator; bridge)
                     ├──► docs/spec/grammar.md        (generated human projection)
                     └──► lib/std/compiler/grammar/roles.id
                              (compact token-role tables + bitsets)
                                     │
              ┌──────────────────────┼───────────────────────┐
              ▼                      ▼                       ▼
        parser (SHC slice)   scripts/treesitter_emit    formatter / LSP / MCP
```

Tree-sitter and the parser derive from the **same** generated `roles.id`, so
control #6 holds by construction; the authored tree-sitter residue (GAP-049)
is retired by generated productions from the same facts.

## 3. Unresolved authority blockers (surface, do not silently select)

1. **C0 `grammar.owed` (constitution.md:1821)** — *"remove bare dot primary;
   preserve postfix named projection; generate every role from one authority."*
   This is an **open C0 reconciliation**. The authority cannot emit a complete
   `primary`/postfix-projection production until C0 settles the bare-dot rule.
   Per the goal, this is surfaced as **BLOCKER-A** rather than resolved by a
   silent grammar choice. (Also C0:1819 `migrate.blocked = "gap[145]"`.)
2. **GAP-145 distinct token identities (Devin-owned)** — text / bytes / compat
   single-quoted / Lua long text / canonical comment / Lua comments / shebang /
   reserved backtick. Roles are identity-keyed; while `KIND_STRING_LIT`
   collapses text/bytes/compat, identity-keyed roles would merge lawsets. So
   the authority's generation is **IMPLEMENTATION-BLOCKED** on Devin's identity
   distinction for the collapsed cases. The authority module can be **authored
   now** with token identity as an input boundary; it cannot **close** until
   GAP-145 lands. **BLOCKER-B.**
3. **MCP transport is broken at HEAD (found this session)** —
   `tools/mcp/duo_bench.id`, `duo_lsp.id`, `zls.id` fail to lex: the production
   lexer rejects the `#!/usr/bin/env duo` shebang (and `--` dash comments) in
   `.id`-suffixed historical transport. None of the three required MCP servers
   can start, so serialized builds, claim acquire/release, and gap updates are
   unreachable. `orient`'s "mcphealth: raw initialize pass" is inconsistent
   with the live failure (dirty tree, active concurrent editing). This is a
   coordination/infra blocker for any authority edit, not a grammar-semantic
   one. **BLOCKER-C** (owned adjacent to GAP-145's lexer work; the transport
   must migrate to canonical lexical forms or be admitted under a compatibility
   lawset with provenance).

## 4. Exact parser-facing role API (keyed by identity, no spelling)

Input: an authoritative token identity `k` (kind id from Devin's immutable
token view) — **never** `token.text`. All results are generated constants.

| Query | Returns | Admitted vocabulary basis |
| --- | --- | --- |
| `grammar.lawset(k)` | canonical \| lua-compat \| duo-historical-compat \| … | C0 §22 lawsets, §7 lua firewall; GAP-145 compat identities |
| `grammar.is_canonical(k)` / `compatibility(k)` | fact | canonical vs compatibility status |
| `grammar.expr_start(k)` | bool | expression-start capability (replaces handwritten list) |
| `grammar.param_slot(k)` | bool | `call.face.declare` parameter-slot eligibility |
| `grammar.prefix(k)` | opt⟨prec, assoc⟩ | prefix role; C0 §5 (e.g. `syntax.anchor.prefix = false`) |
| `grammar.postfix(k)` | opt⟨prec, assoc⟩ | postfix role; includes static-named projection `.` (`grammar.owed`) |
| `grammar.body_start(k)` | declare-face body-start role | `call.face.declare` + `syntax.block` offside |
| `grammar.delimiter_role(k)` | ordinary_application \| structured_pack \| computed_projection \| static_projection \| descriptor_subject_home \| anchor | closed delimiter law (grammar.md) |

Precedence/associativity are **grammar provenance** (C0 :2999/:3037), carried
here, not semantic identity and not a host table.

## 5. Performance representation (constant-time, no hot-path text search)

Mirror the proven `classify.id` shape, extended from keyword categories to
**roles**:

- Dense array `roles: [N]Role` indexed by token kind id (0..~109). Each `Role`
  is a packed record: `prefix_prec`, `prefix_assoc`, `postfix_prec`,
  `postfix_assoc`, a flags bitset, and a `lawset` tag. One array index = O(1).
- Fixed bitsets over kind ids for category membership:
  `expr_start`, `param_slot`, `prefix`, `postfix`, `body_start`, `canonical`,
  `compat`. Membership = one bit test.
- No string compare, no hashmap, no heap object on the recognition hot path.
  A coverage/fuzz gate asserts the parser performs no `==` on `token.text` and
  no spelling lookup in the recognition path (control #5).

## 6. Adversarial controls — how the design proves each

1. **Spelling change, identity fixed → role unchanged.** Roles index by kind
   id; a differential fixture renames a keyword's source spelling while holding
   its kind id and asserts identical role output.
2. **Identity change, spelling fixed → role changes.** Two identities sharing
   spelling (canonical text vs compat text, post-GAP-145) project different
   `lawset`; differential asserts same bytes + different kind id → different
   `lawset`/role.
3. **Add/remove a grammar case → owner + projection change, not consumers.**
   Consumers read generated `roles.id`; adding a prefix operator edits
   `grammar.id` → regenerates tables → every consumer sees it with no
   per-consumer edit.
4. **Canonical and compatibility faces distinct.** `lawset(k)` is per identity;
   distinct kind ids (post-GAP-145) → distinct lawset → never merged.
5. **No token-text search.** Recognition uses array-index + bitset-test only; a
   gate forbids `token.text` compares on the hot path.
6. **Tree-sitter/parser derive from one authority.** Both consume generated
   `roles.id`; the authored tree-sitter residue is retired by generated
   productions from the same facts.

## 7. Remaining GAP-134 prerequisite (the exact next step, in order)

1. **Settle C0 `grammar.owed`** (bare-dot-primary) — one explicit C0 decision.
   Authority blocker; not for this lane to decide unilaterally. (BLOCKER-A)
2. **Land Devin's GAP-145 distinct token identities** (text/bytes/compat/
   comment/shebang/backtick at minimum) so roles can be identity-keyed.
   (BLOCKER-B)
3. **Repair the MCP transport** (BLOCKER-C) so serialized builds, claims, and
   gates are reachable for the authority edit and its differentials.
4. **Then** author `lib/std/compiler/grammar.id` (canonical machine-readable
   owner, identity as input boundary) + the generator emitting grammar.md and
   `roles.id`; rewire `scripts/treesitter_emit.id` and the parser to consume
   them; land the six differentials above as positive/negative/fuzz controls.

Until 1–3 land, the next parser slice is `IMPLEMENTATION-BLOCKED` (as GAP-134
already records). The grammar-authority lane's correct move this session is
this report + the owner design, **not** an authority edit.

## 8. What this session changed

- `.pi/` tooling projection for pi (settings, `idol-dev` skill + scripts,
  `idol-mcp` extension). Non-authority; pi's namespace, analogous to
  `.cursor/`/`.codex/`. Not committed (a new tree addition; commit is a
  separate, claim-governed decision).
- No Idol authority file edited. No claim acquired (MCP unreachable). No gate
  run against an authority diff.
