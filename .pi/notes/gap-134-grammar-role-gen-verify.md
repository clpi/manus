# GAP-134 grammar-role generator — verification (no edit needed)

Lane: grammar-authority (canonical grammar authority → generated compact grammar
roles). Not Idol authority. Records the verification performed for the goal
"MAKE THE GENERATED GRAMMAR ROLE SYSTEM REAL."

Tree: `clpi/duo` @ HEAD `546598b`, dirty, concurrent lanes active.

## Ownership and file state (identified first, per goal)

All three files are **untracked working-tree** creations of a concurrent agent
(last edited 16:20–16:29), not staged, not committed:

| Path | Role |
| --- | --- |
| `src/grammar_roles.zig` | canonical grammar-role **owner** (facts keyed by `lexer.TokenKind` ordinal) |
| `src/grammar_role_gen.zig` | **emitter** → `lib/std/token/grammar_role.id` |
| `lib/std/token/grammar_role.id` | generated compact **projection** (7 tables + 7 role_* lookups) |

No live claim overlaps these paths (checked `.agents/session/claims/`). The
`codex_treesitter_projection` claim covers only `scripts/treesitter_emit.id`
and tree-sitter output — disjoint.

## The described failure is NOT present

Goal: generator "assumes a nonexistent enum `fields` member." In the current
working tree the reflection uses the **correct** pinned-Zig members
(`std.builtin.Type.Enum` in `lib/std/lang.zig:801`):

- `.field_names: []const [:0]const u8`  ✓ used
- `.field_values: []const comptime_int` ✓ used (in a comptime `blk:` + `inline for`)
- there is NO `.fields` member and NONE is referenced (grep confirms).

Evidence the grammar files compile under the pinned Zig
(`0.17.0-dev.1567+f0354179a`):

1. Isolated replication of the exact comptime `blk:` reflection pattern
   (`@typeInfo(E).@"enum"` + `for (field_names, field_values, 0..)`) compiles
   and runs (`rows=4 dot.v=true`).
2. `zig test src/grammar_roles.zig` reaches **link errors only**
   (`undefined symbol: _duo_keyword_classify`, lexer C funcs) — i.e. full
   semantic + comptime analysis of `grammar_roles.zig` **passes**; the link
   failure is missing C objects in a bare `zig test`, not a code error.
3. Full `zig build`: grep for `src/grammar*` errors is **empty**. The build's
   errors are entirely in other lanes' files (`src/sema.zig:3042`
   application-authority error-set mismatch on `recordCompileApplication`,
   plus one other) — out of this lane's ownership.

## Emission verified faithful to the owner

`grammar_role.id` regenerated at 16:29 (after the 16:20/16:22 source edits →
current). `ROLE_COUNT=110`, `KIND_EOF=109` (match `lib/std/compiler/token.id`).
Spot-checks of emitted tables vs `grammar_roles.zig` owner all pass:

- `BEGIN_EXPR[name=0,int_lit=1]=1`; `[dot=80,backtick=84]=0`
- `POSTFIX[dot=80]=1`; `PREFIX[not=21, bang=83]=1`
- `PARAMETER[colon=78]=1`
- `COMPAT_ONLY[string_lit=3, backtick=84]=1`
- `PRECEDENCE[plus=64]=5, [star=66]=6, [dot=80]=10`; `ASSOC[plus=64]=1 (left)`

## Goal criteria

1. **Compile under pinned Zig** — ✓ (this lane's files; full green build blocked
   by `sema.zig:3042`, a different lane).
2. **Derive roles from canonical grammar owner** — ✓ (`grammar_roles.zig`,
   identity-keyed over `TokenKind` via reflection; never spelling).
3. **Emit compact parser-consumable data** — ✓ (7 dense tables + 7 O(1)
   identity-keyed `role_*` lookups in `grammar_role.id`).

Required capabilities, using the owner's existing vocabulary (no invention):
canonical/compat → `compat_only`; expr-start → `begin_expr`; prefix/postfix →
`prefix`/`postfix`; precedence → `precedence`; associativity → `assoc`;
parameter/body → `parameter`.

## Forbidden solutions — absent (grep-confirmed)

No handwritten keyword tables, no punctuation lists, no parser-local precedence
arrays, no text comparisons in `grammar_role.id` (no `=="..."`/`strcmp`/`byte`
compares). Roles index by kind ordinal.

## FTCFTW — satisfied

Compact: dense `[110]` arrays indexed by `@intFromEnum(kind)`. Constant-time:
array index + bit test (`BEGIN_EXPR[kind+1] != 0`). No runtime grammar object
graph.

## Adversarial controls

1. Spelling change, identity fixed → role unchanged — structural: rows keyed by
   enum tag ordinal, not spelling.
2. Identity change, spelling fixed → role changes — verified: collapsed
   `string_lit` projects `compat_only=1` while canonical `text_lit`/`bytes_lit`
   project `compat_only=0`.
3. Add/remove case → owner + projection, not consumers — structural: edit
   `grammar_roles.zig` switch → regenerate → all consumers read `role_*`.
4. Canonical vs compat distinct — `compat_only` per row.
5. No token-text search — grep-confirmed.
6. Tree-sitter/parser from one authority — **partial**: parser can consume
   `grammar_role.id`; `scripts/treesitter_emit.id` is a SEPARATE projection
   (Codex's claimed lane) and does not yet consume it. Out of this lane.

## Blockers (surfaced, not owned by this lane)

- `src/sema.zig:3042` — application-authority error-set mismatch
  (`recordCompileApplication` returns `InvalidImportedApplication`/
  `ApplicationOutcomeConflict` not in `SemaError`). Semantic-graph/application
  lane. Blocks full `zig build`; not the grammar files.
- MCP transport still broken (production lexer rejects the `#!/usr/bin/env duo`
  shebang in `tools/mcp/duo_bench.id` etc.), so `duo-bench` claim coordination
  is unreachable. Used the durable claim view instead.

## Action taken

**No Idol-source edit.** The generator is already real and correct in the
working tree; editing correct concurrent work would violate "do not overwrite
concurrent work." This note is the verification deliverable. Cursor (parser
lane) can consume `lib/std/token/grammar_role.id` (`role_*` lookups) with no
local spelling knowledge — the goal's STOP condition is met for this lane.
