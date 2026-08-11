# Directives — the recorded owner ruling ledger

`pass120.md` §21 requires every owner directive to be recorded here with date,
verbatim wording, and scope, because a later session otherwise finds only pass
text. `law.owner` (constitution §3) reconciles each current directive into the
constitution before implementation continues. A pass document or projection
that contradicts a recorded directive is void on its face. A ruling that cannot
cite a directive here may not overturn one.

Precedence (constitution §3 `law.owner`): owner directive > constitution >
projection > implementation > history.

## 2026-08-08 — G-DOM retired

- Verbatim: "dominates shouldnt be a thing its just an artifact of claude"
- Scope: the `ward@dominates(wart)` relation is retired from Idsem vocabulary.
  The wasm runtime lives in `tools/wasm/` and is measured by `zig build
  runtime-bench` against wasmtime, wasmer, and wart, publishing its LOSSES,
  with every runtime required to produce the SAME ANSWER before any speed
  comparison.
- Effect: no `dominates` law exists in the constitution; source may not write
  it. Enforced by `scripts/idiomgate.duo`.

## no new std — standing directive

- Verbatim: "no std" — std is migration distribution, never semantic
  architecture. New canonical `std.*` APIs and call sites are forbidden;
  `std.script` is frozen migration debt.
- Scope: possessed values supply subjects, authority belongs to worlds,
  qualification belongs in facts. No replacement universal namespace
  (`core.*`, `system.*`, `runtime.*`, `process.*`, `fs.*`, `os.*`, `idsem.*`)
  may be admitted as native semantic authority.
- Effect: reconciled under `law.authority`; enforced by `scripts/idiomgate.duo`,
  which blocks every added line that writes a `std.` capability traversal.

## 2026-08-10 — primitive zero

- Ruling: no fixed-width primitive descriptor identity is minted, and no
  literal is forced into a machine width without demand. An unannotated
  integer literal retains its exact integer value without a default fixed
  width.
- Scope: fixed-width source faces (`i8` … `i64`, `u8` … `u64`, `f32`, `f64`)
  remain compact canonical source faces; numeric behavior derives from semantic
  numeric meaning plus observable width, sign, precision, format, overflow,
  rounding, and ABI facts.
- Effect: reconciled into `law.number.projection` and `law.construct.zero`;
  `gaps/GAP-149.md` supersedes the retired irreducible scalar-descriptor table
  in `docs/spec/numerics.md`.

## Language identity

- The language is Idsem. Canonical source files use `.id`; the binary is
  `idsem`. `duon`, `duo`, and `.duo` are history and migration provenance.
- Reconciled: constitution §4 `language`.

## Mechanics

- A current explicit directive is reconciled into the constitution before
  implementation continues (`law.owner` binds).
- A conflicting projection is void and repaired, never treated as a second
  authority.
- Reversing a directive requires a new recorded directive; pass text alone
  cannot reverse one.
