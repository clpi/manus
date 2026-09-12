| field | value |
|---|---|
| title | Brief — OpenCode Big Pickle: reduction + evidence tooling |

| # | directive |
|---|---|
| 1 | IDOL REDUCTION + EVIDENCE TOOLING — OPENCODE BIG PICKLE ======================================================= You own tooling and tests, not language or compiler semantics. |
| 2 | Expected base: <resolved to current HEAD at assignment> Acquire exact new-file/tool claims. |
| 3 | Forbidden: docs/spec/** src/parser.zig src/sema.zig src/semantic_graph.zig src/subject_home.zig src/native_ir.zig src/dnir_lower.zig src/native_backend.zig tools/wasm/src/engine.id MISSION A — REDUCER Implement a reducer whose predicate is an external command plus expected outcome. |
| 4 | Supported predicates: crash/signal exact first diagnostic output mismatch exit mismatch graph digest mismatch machine/object mismatch interpreter/JIT mismatch performance threshold Reduction must preserve valid source-family handling and must never accept a different earlier failure as success. |
| 5 | Add selftests proving: a crash reduces a wrong answer reduces an exact diagnostic reduces a deliberately broken predicate is rejected restoring removed text restores the original predicate MISSION B — METAMORPHIC GENERATOR Generate bounded paired tests for already-ruled equivalences only. |
| 6 | Do not invent equivalence laws. |
| 7 | Read equivalence pairs from an explicit data file or existing gate authority. |
| 8 | MISSION C — PERTURBATION HELPER Implement reusable checks: exact before match count exact after match count changed source hash changed binary hash red test after damage exact restoration hash A no-op perturbation must fail the helper. |
| 9 | MISSION D — EVIDENCE SUBJECT Provide one reusable schema/helper carrying: repository commit dirty state compiler path/hash target oracle command requested inner status artifact hashes selected realization Integrate it into exactly one existing gate as proof. |
| 10 | MISSION E — GRAMMAR PARITY Compare existing token/role/tooling projections by token identity. |
| 11 | Report drift only. |
| 12 | Never rewrite a grammar role automatically. |
| 13 | VALIDATION focused selftests one positive control one negative control one deliberate damage control repo hygiene no compiler semantic files modified Final report must explicitly state: semantic vocabulary delta = 0 semantic compiler behavior delta = 0 |

| section |
|---|---|
| Reduction phases (Mission A) |

| # | directive |
|---|---|
| 1 | remove files/homes, remove declarations, remove statements, remove branches, simplify expressions, simplify structured packs, reduce descriptors, reduce world facts, reduce inputs. |
| 2 | Every candidate must be parsed/validated before predicate testing. |

| section |
|---|---|
| Metamorphic pair families (Mission B — already-ruled only) |

| # | directive |
|---|---|
| 1 | operand-first ↔ subject-first; canonical ↔ compatibility face; explicit default ↔ omitted default; structured result ↔ demanded scalar projection; file spelling / home spelling variants; familiar control ↔ canonical control; direct ↔ Wasm where admitted; interpreter ↔ JIT. |

| section |
|---|---|
| Grammar projection surfaces (Mission E) |

| # | directive |
|---|---|
| 1 | TokenKind, grammar_roles, Tree-sitter, formatter admission, LSP metadata, grammar docs. |
| 2 | Compare by token identity; do not choose which side is correct. |
