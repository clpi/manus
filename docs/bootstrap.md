# Idol bootstrap contract

| # | directive |
|---|---|
| 1 | No executable compiler-B/C evidence producer exists yet. |
| 2 | The seed remains the host compiler; it does not obtain bootstrap authority from a project-owned source model. |
| 3 | This document is a human projection of the executed authority frontier, not bootstrap evidence or production authority. |
| 4 | The immediate target is compiler B, not a sovereign backend. |
| 5 | No compiler B exists. |

| # | directive |
|---|---|
| 1 | **Progress dashboard:** three dominant metrics and normalized audit scores live in [`docs/METRICS.md`](METRICS.md). |
| 2 | Subordinate diagnostics (file counts, Zig counts, keyword counts) must not headline status reports. |

| # | directive |
|---|---|
| 1 | **Evidence-subject (`law.evidence.subject`):** live tree is not automatically the measured program. `59093d7b` is an evidence revision whose subject is `29f62035`. |
| 2 | Do not report FTCFTW or unit aggregates “at HEAD” unless the measured subject equals the live tree. |
| 3 | FTCFTW is **invalid** as a performance claim. |
| 4 | No compiler B exists. |

| # | directive |
|---|---|
| 1 | **Critical path to B:** source-family → lexical identity (GAP-145) → grammar role (GAP-134) → parser → exact graph → demand → **one representation decision** → specialization (budgeted) → direct realization → object → evidence → B → C. |
| 2 | Eight production lanes live in `.agents/AGENT_COORDINATION.md`. |
| 3 | Do not start a parser slice that reconstructs or outruns GAP-145; a bounded joint transfer must consume producer facts and delete the replaced host decision in the same diff. |
| 4 | Do not let later passes re-decide boxing/stack/register/heap. |

## Current stage: S0

| # | directive |
|---|---|
| 1 | **S0 (active):** the pinned Zig seed produces the host compiler. |

| # | directive |
|---|---|
| 1 | A production host-built `idol` executable exists. |
| 2 | No compiler B built from canonical Idol compiler source exists. |
| 3 | Host `idol check` / `idol run` are not self-host proof. |

| # | directive |
|---|---|
| 1 | The production front end nevertheless has twenty-six bounded executed Idol-owned boundaries: the lexer producer and twenty-five parser decisions. |
| 2 | The executed production file `lib/compiler/lexer.id` owns token-kind production, token content, and exact source spans. |
| 3 | Its `.id` suffix is not evidence of canonical source or compiler B. |
| 4 | The host bounds-checks those spans and projects them into its temporary parser representation. |
| 5 | It does not reconstruct token text or source locations. |
| 6 | Canonical lexical identity is not closed (`GAP-145` OPEN): producer identities for text/bytes/compat/long, `#` comment, shebang, dash comments, and reserved backtick now cross `tokenize()`. |
| 7 | Producer `KIND_STRING_LIT` and host `TokenKind.string_lit` and AST `.string_lit` are deleted without renumbering live producer slots |
| 8 | Tree-sitter and quote/source-law consumers remain. |
| 9 | The historical `lib/` distribution path is retired filesystem provenance (GAP-157), not semantic ownership. |

| # | directive |
|---|---|
| 1 | The production route is now fail-closed. |
| 2 | Allocation, record-buffer, and token projection failures leave no accepted token stream and return an error to the caller; they no longer return success and resume the host scanner. |
| 3 | The host scanner remains a differential oracle. |
| 4 | This removes one automatic host semantic fallback, but it does not close the missing canonical lexical identities in `GAP-145`, the generated grammar roles in `GAP-134`, or later code-generation fallbacks. |
| 5 | Module-embed callers still convert a route error into a declined embed or optimization path; deleting those higher-level fallbacks requires the corresponding realization owner to distinguish physical refusal from semantic failure. |

| # | directive |
|---|---|
| 1 | Source ingress classification is now executed Idol authority. |
| 2 | The producer owns physical forms, corpus roles, longest-match admission, unlisted fallback, law, and provenance through `sourceform*`, `sourceentry*`, and `sourcefact*`. |
| 3 | Zig normalizes a physical file to one repo-relative provenance spelling, calls the producer once, and binds returned names to the temporary host ABI; it owns no role roster or role→law mapping. |
| 4 | Production lexing now goes through the Idol lexer (`tokenize()`); host `tokenizeHost()` is differential-only. |
| 5 | The identity blocker is `GAP-145` remaining consumers (Tree-sitter and source-law collapse) before a complete parser stage. |
| 6 | Physical producer slot 3 remains unpublished and fails closed; it is not a token identity. |
| 7 | Parser long-bracket reconstruction is deleted (level in `int_val`). `GAP-134` now has generated roles (separate semantic identity count and physical slot span, `body_start`, infix). |
| 8 | The same owner now also generates the relation and prefix identities plus the infix, update, and glued source-face facts. `src/ast.zig` aliases that generated ontology; parser recognition and the pretty-printer consume it rather than maintaining token-to-operation and operation-to-token maps. |
| 9 | Canonical `return` is the first live `begin_expr` consumer; match-arm discovery now consumes `pattern` through the same immutable view without save/scan/restore; body-start and header-infix are also role-owned. |
| 10 | Callable-header, return-value-start, and match-arm-clause classification now execute from `lib/compiler/parser.id` over a compact projection of that producer pack; their replaced Zig decisions are deleted. |
| 11 | The gap is not closed. |
| 12 | Porting the rest of the host recognizer would duplicate grammar authority through token-text lists and mutable lookahead, so S0 remains the honest stage while each bounded decision crosses with its host body deleted. |

| # | directive |
|---|---|
| 1 | The transfer must also preserve PREDICATE-ZERO. |
| 2 | Parser and resolver output retain cases, refinements, descriptor and world facts, unknowns, demands, and transitions directly. |
| 3 | It must not reproduce host `has`, `is`, `can`, `exists`, sentinel, or query-then-mutate helpers as Idol semantic architecture. |

## Production authority ledger

| Boundary | Current state | Exact remaining authority |
| --- | --- | --- |
| Source ingress | IDOL OWNED, HOST FS/ABI BRIDGE | `lib/compiler/lexer.id` executes physical-form and corpus-role admission and returns exact law/provenance. `src/lexer_bridge.zig` only resolves physical provenance to the producer's repo-relative spelling and binds producer names to temporary host enums. The roster is a deletion bridge until launch/provider ingress supplies explicit law facts. |
| Lexer producer | IDOL OWNED | `lib/compiler/lexer.id` owns token-kind, content, and span production and fails closed. Canonical lexical-law closure remains `GAP-145`. |
| Canonical `.id` lex route | IDOL OWNED | `src/lexer_dispatch.zig` `route()` calls `tokenize()` for every source. The obsolete `TokenizeAuthority` enum/query is deleted: production has no host/generated selector. Host `tokenizeHost()` is differential-only (legacy-equivalent subset; must not veto intentional Idol divergence; `law.bridge.death`). Generated `src/lexer_tokenize.c` is from current `lib/compiler/lexer.id` via `dump-c --lib`. Every lexer export takes family as an operand (`law.family.one`); `new()` does not read suffix bytes. Production compile, fmt, and embed call the `sourceFacts` bridge once, then `Lexer.initFacts`; the law/provenance answer is executed Idol output. `route()`, parse, sema, and token-view consume `lex.family`. `Lexer.init` is a test convenience. |
| Lexer ABI schema | IDOL OWNED, GENERATED HOST BRIDGE | `RECORD_SLOTS` / `lexErrorFromCode` / `tokenKindFromOrdinal`, the host-authored `TokenKind` enum, `kindFromRecord`, `useDuoTokens`, `Lexer.duo_tokens` / `duo_index` / `duo_next`, and `token_view.fromLexer` are deleted. Record decode validates through the owner-generated sparse enum and route returns one immutable slice. Parser alone owns its pack/index and snapshots that index on every speculative read; Lexer retains only the host differential cursor. Remaining bridge debt is the generated enum still carried by parser tokens and consumed by host kind switches (`law.bridge.death`, GAP-107). |
| Lexical identity | IDOL OWNED, GAP-145 OPEN | Text/bytes/compat/long, `#` comment, shebang, `--` / `--[[` comments, and reserved backtick cross `tokenize()`. Long-text delimiter level is `int_val`; parser no longer scans `[[`. Producer, host-token, and AST `string_lit` identities are deleted; physical slot 3 is unpublished. AST `.quoted` retains exact quote provenance without a text/bytes taxonomy. Tree-sitter literal/comment identities are owner-derived; the generated token enum, host kind consumers, and semantic quote/source-law observers remain. Twenty-five executed parser decisions are not lexical closure or complete parser SHC. |
| Token/span | IDOL OWNED | Exact token content spans are projected through the generated-C physical bridge; the host retains a temporary parser representation. The unused `ProductionPack` / `tokenizePack` / `fromPack` parallel API and the duplicate Lexer cursor are deleted; production has one `route` whose returned immutable slice is owned and advanced only by Parser. |
| Grammar roles | IDOL OWNED, GAP-134 partial | `lib/compiler/token.id` is the **one executable grammar-fact owner** (`law.grammar.one`): token identities; roles; precedence and associativity; relation and prefix identity; and infix, update, glued, layout, static-member, block-boundary, branch, direct-statement, and admission facts. `lib/compiler/parser.id event` projects dispatch/admission/member/boundary/branch/return/end/layout/empty facts for every token in the immutable pack in one call. The generated `TokenKind` bridge remains and most parser recognition is host-executed. |
| Parser recognition | IDOL OWNED SLICES, HOST MAJORITY | Nine graph-proven public relations plus private bounded relations execute twenty-five decisions from producer facts. `event(facts,count,out,capacity,idol)` capacity-checks before mutation and produces two contiguous physical words per token; Parser caches that array beside `parser_facts` and indexes both with its sole cursor. Lane-two bit 6 settles exact contextual `type` alias head versus `type(value)` once from the producer word and following identity; bit 7 propagates an already-settled callable header backward over direct, dotted, or subject-specialized name paths. Four Zig consumers select each face; no type-text classifier or bare-path scanner remains. Member, opening, empty-body, and every dynamic boundary consumer read event bits through the one public `boundary` relation. Standalone member, opening, layout-terminator, empty-body-terminator, and direct layout-verdict ABIs are deleted. `boundary(opening,...)` returns either the physical opening frame or the edge action and privately executes `_layout_verdict`; no token row or raw kind is re-read there. `@` lookahead, statement internals, and most expression recognition remain host-executed. This is a production whole-pack foothold, not complete parser SHC or Compiler B. |
| Binding/scope | HOST OWNED | Production binding and scope construction remain in the host parser and semantic producer. The graph now retains one module binding id across declaration, reassignment, checked application operands and shadowing controls; checked names nested in application operand expression trees publish an exact value → binding → descriptor route. Nested function/block bodies are outside that bounded producer domain. |
| Semantic construction | HOST OWNED | The graph work is an improving host implementation, not executed compiler-B source. |
| Relation/application resolution | HOST OWNED | Production resolution remains host-executed; exact graph application authority is still under integration. GAP-214 closes checked nested-name descriptor continuity into DNIR even when the containing bootstrap call is unresolved, but does not manufacture an `ApplicationFact`; aggregate/index/foreign-field projection → result identity remains open. |
| Demand | HOST OWNED | No executed Idol compiler demand stage exists. |
| Lowering/realization | HOST OWNED | Host lowering and realization select the artifact path. |
| Machine selection | HOST OWNED | Host code selects direct native or generated-C realization. |
| Object emission | HOST OWNED | The native object emitter is host implementation and production lineage is incomplete. |
| Runtime/link selection | HOST OWNED | Host code still selects runtime support and link behavior. |
| Assembler/linker execution | FOREIGN REALIZATION ONLY | Foreign tools perform physical realization after the host selection. |

| # | directive |
|---|---|
| 1 | For the fail-closed lexer transfer: |

- **BEFORE:** a storage failure returned success without installing the Idol
  token pack, so the next parser read silently resumed the host scanner.
- **AFTER:** the same failure propagates, partial route storage is released, and
  no host token stream is accepted by that route.
- **NEXT:** Tree-sitter literal, numeric, keyword-literal, and comment identity
  rules are owner-derived and mechanically pinned; the remaining `GAP-145`
  boundary is the generated token enum plus host kind consumers and semantic
  quote/source-law observers. Source-form and corpus-home admission execute in
  Idol; filesystem normalization and host enum binding remain explicit bootstrap
  bridges. `GAP-134` executes twenty-five parser decisions and Parser owns the sole
  immutable pack cursor. Public `event` now settles the complete per-coordinate
  word: statement/admission/member/boundary faces in bits 0..16; primitive,
  literal, quoted, prefix, demand, and trivia-aware line-head facts in bits
  17..22; Pratt relation/precedence/associativity in bits 23..46; and unary,
  glued-update, and single-token update ordinals in bits 47..61. The standalone
  `lead`, `prefix`, `demands_operand`, `infix_prec`, primitive/literal/quoted,
  `_unary`, `_glue`, and `_update` relations and host-facing C ABIs are deleted.
  A second contiguous event lane now carries match face in bits 0..1, return face
  in bits 2..3, both callable-header variants in bits 4..5, contextual `type`
  alias head in bit 6, and bare declaration head in bit 7. Previous visible
  identity, line opener, return line, contextual word, nesting, and separators are
  derived while the pack executes; Zig selects settled faces only. The direct
  header, return, and match ABIs are deleted; all five contextual type text
  decisions plus the four-call bare-path scanner are deleted, leaving exactly
  `event` and `boundary` as parser externs. The handwritten maps, copied orders, runtime name
  scan, and dead host relation facades are gone. Parser staging, statement/
  expression structure, and AST construction remain host-executed; this is not
  complete Parser SHC or Compiler B.

| # | directive |
|---|---|
| 1 | Canonical source ingress recognizes `.id` as Idol. |
| 2 | New canonical `.id` is admitted. |
| 3 | Retired `.duo` / `.duon` / `.idsem` are not source suffixes. `.lua` remains foreign compatibility input. |
| 4 | Tracked noncanonical `.id` content remains SOURCE-ZERO debt and must reach zero; the `.id` extension itself is not debt. |
| 5 | Compatibility testing must move to generated, structured, or external material rather than an in-tree stale source library. `src/lexer_bridge.zig` is one bootstrap helper, not source-family authority. |
| 6 | It normalizes filesystem provenance and consumes the executed producer's exact law/provenance answer. |
| 7 | Build entry, embedded module discovery, and direct-native module metadata discovery consume that fact. |
| 8 | Tooling and corpus gates that still enumerate `.id` independently remain migration bridges, not bootstrap evidence. |

| # | directive |
|---|---|
| 1 | Suffix-independent semantic identity is not closed by the existing differential. |
| 2 | Byte-identical object output demonstrates only one realization result; it does not prove equality of every normalized graph fact. `GAP-142` owns the exact identity and continuity boundary. |
| 3 | Until the complete checked-fact comparison passes, suffix and path influence remain unclosed rather than being inferred from machine equality. |

| # | directive |
|---|---|
| 1 | Active bootstrap bridges (lock scripts, generated C lexer tables, physical tool aliases) remain only while `law.bridge.death` records owner, replacement, and deletion condition in `docs/bootstrap.md` or an open gap. |
| 2 | Delete each bridge when its condition is met — do not relocate to legacy paths. |

| # | directive |
|---|---|
| 1 | The former synthetic bootstrap verifier was deleted. |
| 2 | It had no production consumer, observed no compiler run, and modeled identity through three invented numeric coordinates. |
| 3 | A real bootstrap projection must consume exact graph ids, facts, witnesses, provenance, and observations from an execution world before the contract can accept B or C. |

| # | directive |
|---|---|
| 1 | `lib/compiler/application.id` is **role documentation only** (decomposed |
| 2 | APPLICATION-CONSUMER-ZERO). |
| 3 | The graph entity is identity. |
| 4 | A coordinate `identity` record or parallel application schema is forbidden. |
| 5 | Agents must not treat that file as canonical application schema or extend it with tables. |
| 6 | Production authority is graph accessors (`applicationRelation`, …). |
| 7 | Production authority begins when exact graph entities and explicit fact cardinality survive graph, demand, realization, and machine lineage without source-name reconstruction. |
| 8 | Audit: `scripts/ledger/application.id`. |
| 9 | Lowering that reads `ApplicationFact.relation` from the graph must not reconstruct subject, operand, result, descriptor, effect, world, witness, demand, or target downstream (`law.application.consumer`). |

| # | directive |
|---|---|
| 1 | **Graph sovereignty (P0, not closed):** `NodeKind` tags are physical indexes only (`law.tag.authority`). |
| 2 | Production query/validity must use published facts (`callable`, `hasDescriptorFacts`, graph accessors) — never `kind == .func` / `.table_shape` / `.module` for meaning. |
| 3 | Audits: `scripts/ledger/graph.id`, `scripts/ledger/application.id`, `gate/graph.id`. |
| 4 | Open: `Card` cardinality on application facts; `ast_ref` semantic reads → 0; columnar fact storage; graph core imports AST/sema/transform — endpoint is GRAPH-SOVEREIGNTY. |
| 5 | Partial: caller-indexed `home_apps` adjacency; `applicationsIn` / `relationsReferencedBy` query API; zero-copy operand views; `nested` reverse index for scope/contains; `descriptor_refs` for recursion walks. |

| # | directive |
|---|---|
| 1 | Generated `src/lexer_tokenize.c` plus host `Token` rematerialization is a **physical** bridge. |
| 2 | Semantic authority is Idol `tokenize()`; the duplicate Lexer pack cursor is gone and Parser owns one immutable view, but compile-time FTCFTW still needs Idol lexer → Idol parser without generated-C call, oversized records, generated enum switching, or host token copies. `lib/` remains retired filesystem provenance (GAP-157), not a semantic namespace. |

| # | directive |
|---|---|
| 1 | Do not claim combined CI green from local ledgers or focused unit runs. |
| 2 | Remeasure the integrated build at the current revision. |
| 3 | Crash count is qualitatively above pass-count (`law.crash.first`). |
| 4 | Every compiler refusal (parser, resolver, world, descriptor, realization, specialization) names application, missing fact, producer, and consumer — not only DNB backend bail. |

## Target chain

| Stage | Input | Output | Proof |
| --- | --- | --- | --- |
| **S0** | Zig + repo source | Host-built `idol` binary (not compiler B) | Remeasured CI/unit/bench at the revision — not assumed from local ledgers |
| **S1 / B** | S0 + canonical Idol compiler source | First Idol-built compiler | Exact graph facts, witnessed correspondence, and behavior vs the seed oracle |
| **S2 / C** | B + identical source | Self-built compiler | Semantic, diagnostic, and behavioral parity with B |
| **S3** | C + identical source | Fixed-point candidate | Artifact comparison and reproducibility bundle |

## Trusted seed requirements

| # | directive |
|---|---|
| 1 | The seed must be: |

- Pinned and checksummed
- Archived and reproducibly obtainable
- Minimal enough to audit
- Clearly separated from canonical Idol compiler source
- Used for bootstrap only — not semantic authority after S2

## Stage comparisons (always required)

- Exact graph identities, facts, and witnessed cross-incarnation correspondence
- Public capability manifests
- Graph-grounded realization facts and causal lineage
- Object structure
- Binary behavior (test matrix)
- Diagnostics parity

| # | directive |
|---|---|
| 1 | Fingerprints may accelerate candidate comparison or summarize evidence. |
| 2 | They never establish B/C semantic identity, correspondence, or lineage. |

| # | directive |
|---|---|
| 1 | The executed foundation now qualifies the one resident graph `id` with an owning graph-incarnation coordinate, freezes registered incarnations, and admits explicit witnessed preserved/replaced/split/merge/generated/retired correspondence facts with checked cardinality. |
| 2 | The public knowledge snapshot projects those exact references and no longer manufactures identity from a kind/name string or fingerprint. |
| 3 | This is not B/C closure: no bootstrap driver yet persists two incarnations, supplies B and C producer witnesses, or compares their complete graph and diagnostic facts. |

## Stage comparisons (when declared)

- Compiler performance baselines
- Binary identity (deterministic builds only)

## Portability and deterministic-evidence admission

| # | directive |
|---|---|
| 1 | The portability decision is locked, but its fleet evidence is not present in this tree. `zig build native-call-control` validates the evidence reader and its damage controls. `zig build native-call` refuses until `IDOL_NATIVE_CALL_FLEET` names one manifest showing an equivalent graph-owned application passing through platform calls on Linux, macOS, Windows, and FreeBSD, plus raw-syscall refusal controls on every non-Linux OS. |
| 2 | This does not mint a `native-call` source kind: callable identity stays fixed and target/ABI/ world facts select a physical call realization. |

| # | directive |
|---|---|
| 1 | Likewise, `zig build artifact-equality-control` validates the keyed equality reader. `zig build artifact-equality` refuses until `IDOL_ARTIFACT_FLEET` names real x86-64, Apple M-series, and Raspberry Pi 5 reports for one identical source/target/configuration/compiler/toolchain-revision key. |
| 2 | Compiler binary hashes are recorded per host and may differ; the produced artifact hash may not. |
| 3 | No cross-target equality is claimed. |
| 4 | Until those real reports exist, portable native calls and cross-host deterministic artifacts are **NOT ADMITTED**, and evidence-fleet measurements depending on either remain blocked. |

## Bootstrap subset

| # | directive |
|---|---|
| 1 | The minimum Idol subset required to compile the next stage is a staged capability level of canonical Idol, not a permanent second language. |

| # | directive |
|---|---|
| 1 | The compiler-critical basis is required capabilities and facts, not named container kingdoms: |

- element width and sequence shape
- view lifetime and alias facts
- table shape
- arena realization option
- vector realization option
- intern correspondence
- bit representation
- source and span provenance
- filesystem read as a subject / world / effect application
- diagnostic output as a subject / world / effect application

| # | directive |
|---|---|
| 1 | Do not resurrect bytes, strings, vectors, maps, or bitsets as permanent native ontologies. |
| 2 | No graph/world-backed projection currently records or observes that basis for B and C. |
| 3 | Filesystem read and diagnostic output still need their subject, world, and effect facts, and production reachability must be observed rather than asserted. `GAP-139` owns that missing evidence boundary. |
| 4 | Adding unrelated standard vocabulary does not advance this contract. |

## FTCFTW constraint

| # | directive |
|---|---|
| 1 | Bootstrap work must preserve maximum semantic knowledge with minimum physical compiler state. |
| 2 | The graph retains meaning; demand deletes work before materialization; realization keeps compact lawful choices until commitment; machine selects the cheapest concrete execution. |
| 3 | Rich meaning does not justify a large runtime, boxed compiler state, or a fully materialized realization program. |

| # | directive |
|---|---|
| 1 | The source-family projection in this stage is one bounded ingress query with no allocation. |
| 2 | It selects one language law and records provenance. |
| 3 | It does not select machine realization. |
| 4 | Equivalent canonical `.id` and temporary compatibility input must normalize to identical semantic entities and facts apart from admitted source provenance; focused byte equality alone does not prove that boundary. |

| # | directive |
|---|---|
| 1 | The direct-native metadata lookup adds two fixed suffix probes per candidate prefix and no allocation beyond the path/source work already required. |
| 2 | Exact focused and aggregate outcomes are volatile evidence and therefore do not live in this contract. |
| 3 | Session bootstrap must bind them to the tested revision, dirty state, command, requested-run outcome, and artifact; unavailable evidence fails closed. `GAP-131` remains an onboarding P0 until that projection reads canonical gap files and live claims. |
| 4 | A focused pass never changes a red aggregate into a pass, and a zero returned by the current broken reader is not evidence of a clean project. |

| # | directive |
|---|---|
| 1 | Future B/C acceptance requires two distinct application and output incarnations, the seed as B's exact producer, B as C's exact producer, identical source content, the same backend and execution-world content, and semantic, behavioral, and diagnostic observations with witness and provenance bound to each application. |
| 2 | No synthetic structural self-check substitutes for those observations. |
| 3 | B and C may have different artifact content; binary identity is not required for B-to-C acceptance. |

## Source-zero deletion gate

| # | directive |
|---|---|
| 1 | Do not add a bootstrap verifier beside the production graph. |
| 2 | The remaining tracked application inventory is migration evidence only; its demanded facts must move into executed `.id` with production perturbation and differential proof before that source is deleted. |
| 3 | A future bootstrap projection derives its evidence from the executed Idol compiler graph rather than making a host build step authoritative. |

## Prohibited claims

- "Self-hosted" when Idol code exists but is not on the production compile path
- Silent fallback. A pinned trusted-seed C/native backend may remain only as
  foreign physical realization with zero Idol semantic authority; it does not
  prove backend sovereignty or authorize new host implementation.
- Undocumented bootstrap binaries or unpinned dependencies
- A B/C comparison built from different compiler source
- File-count reduction presented as compiler authority transfer
- Synthetic verifier controls presented as observed bootstrap evidence
