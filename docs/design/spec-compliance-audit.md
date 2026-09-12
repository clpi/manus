# Spec-Compliance Audit — Definitive 20-Point Specification

| # | directive |
|---|---|
| 1 | **Repo:** `/Users/clp/work/idol-main`, branch `main` **Audit commit:** `fedef9e0` (HEAD at audit start; repo was mid-push — commits at 22:21–22:38 PDT) **Date:** 2026-09-11 **Mode:** read-only analysis. |
| 2 | No source files modified. `native.id` and the 7 performance fixes are owned by the sibling fixes workstream; this audit sequences *after* their work ships. **Method:** static inventory over tracked files + empirical probes with the built compiler (`zig-out/bin/idol`, built 2026-09-09) on throwaway files in `/tmp` (never in the repo). |

## Verdict summary

| # | Spec point | Status | Violation count (measured) |
|---|------------|--------|----------------------------|
| 1 | Zero comments — absolute | VIOLATED | 830 / 1473 `.id` files contain `#`; 256 / 277 `lib/` files |
| 2 | Real-time cross-device via one canonical surface | VIOLATED | 37 scripts in `~/.hermes/scripts/` (outside repo) + `coord/cron/*.sh` + `bin/idol-main-mcp.sh`; in-repo `channels/` and `subscriptions/` are empty |
| 3 | Idolic violations IMPOSSIBLE — checker must reject, not warn | VIOLATED | proven empirically: `idol check` exits 0 on `_`, camelCase, and `#` comments |
| 4 | No underscores anywhere ever; no mashed compound words | VIOLATED | 898 tracked files with `_`; 40+ distinct underscored identifiers in `lib/`; mashed/abbrev compounds throughout `native.id` (`wjmp`, `wrl`, `purecount`, …) |
| 5 | No camelcase; no names decomposable to an existing graph edge | VIOLATED | camelCase in 30+ `lib/` files (`commaSep1`×19, `findFunc`×16, …) |
| 6 | Faster than fastest oracles, proven | VIOLATED | `bench/RESULTS.md` (2026-09-11): idol loses to clang on sum (−1138.88%), arith (−30.64%), fib (−0.93%) — owned by fixes workstream |
| 7 | Preserve intent: `.1 + .2 == .3` | VIOLATED | v5 has no decimal literals (`native.id` `num()` parses digits only); full path `idol run` errors: `wasm32-wasi: no native realization (UnsupportedProgram) … f64-slot-in-integer-position` |
| 8 | No shell/python IN THE REPO | VIOLATED | 147 tracked `.sh` + 11 tracked `.py` = 158 files; 15 `lib/` files embed `os.execute`/`io.popen` |
| 9 | Names decomposable to existing graph edges MUST be decomposed | VIOLATED | `fs_exists`→`fs:exists`, `str_join`→`str:join`, `read_i64`→`read:i64`, `make_concept`, `token_view`, `register_import`, … |
| 10 | Folder info in deterministic runtime/meta graph, no loose files | VIOLATED | no folder-membership graph found; `channels/`, `subscriptions/` empty unclaimed dirs; `.agents/census/zerohistory.baseline` is a single count, not a graph |
| 11 | No blockers | VIOLATED | 125 open GAP files under `gaps/` |
| 12 | No bloated stdlib | VIOLATED | 277 `.id` files in `lib/`, 31 subdirs; duplicates (`str.id`/`string.id`/`strings.id`, `db.id`/`database/`, `math.id`/`math/`); STD-ZERO ledger: 350 code sites with `std.` tokens; `lib/meta.id` itself defines `std_meta_typeof` |
| 13 | Proof assistant = programming language (unified) | VIOLATED | proving is `tools/wasm/proof.sh` (shell+zig+cc+wasmtime+wart) and Zig `idol prove`; `lib/proof/*.id` is 247 lines of string helpers, not a prover |
| 14 | No intermediaries (no C/assembler/linker in final path) | VIOLATED | `lib/compiler/emit_c.id`: "canonical path today" is Duo→`emit_c`→`cc`→`a.out`; `lib/pipeline.id` generates C via `@c.emit`; `lib/mem.id:176` `@comp.c.emit([[…C…]])`; `lib/jit.id:46` embedded C; 631 `.c` files under `src` `lib` `tools` `bench`; `proof.sh` uses `cc -std=c11` off-Darwin |
| 15 | Idol-native ways MANDATORY in Idol's own code (functional/chained, not for/while/if) | VIOLATED | 170/277 `lib/` files use `while`, 248 use `if`, 211 use `for`; `native.id`: 20+ `while`, 40+ `if` |
| 16 | Compact operators (`and`/`or`/`not`) where more compact | VIOLATED | `!` for `not`: `lib/script.id:32`, `lib/proof/tac.id:60`, `lib/compiler/parser.id:312`; `&&`/`||` inside generated logic strings `lib/contracts.id:78–82` |
| 17 | NEVER sentinels | VIOLATED | `lib/compiler/native.id:61,69,134` `return 0 - 1`, `:463` `== 0 - 1`; `lib/slices.id:56,66`; `lib/sort.id:157`; `lib/compiler/emit_c.id:106,113,127`; `lib/compiler/lexer.id:830,845`; `lib/meta.id:278–284` `return -1`; `lib/json.id` documents a "Sentinel" |
| 18 | Familiar faces preserved for user interop, NEVER in family code | VIOLATED | same corpus as #15; user-`while` compilation itself is correctly preserved (`native.id` while-handling) |
| 19 | Files are table scope; `M = ; M` inventory; dirs imply table; root `table/`+`table.id` layout | VIOLATED | 10 `lib/` dirs lack root `table.id` (`compiler`, `compress`, `database`, `encoding`, `index`, `ml`, `target`, `testing`, `text`, `token`); `lib/live/` has no `live.id`; 38 files end with bare `M` (inventory below); no literal `M = ; M` with semicolon found (semicolon correctly denied) |
| 20 | Maximally performant, proven | VIOLATED | same evidence as #6; owned by fixes workstream |

| # | directive |
|---|---|
| 1 | No spec point is fully compliant. |
| 2 | Points #6/#20 are owned by the fixes workstream (do not touch); everything else is sequenced below. |

## Per-point violation inventory

### #1 — Zero comments (absolute). VIOLATED.
- `grep -rl '#'` over tracked `.id`: **830 of 1473** files (56%), including **256 of 277** `lib/` files.
- Representative: `lib/fn.id:1–4`, `lib/iter.id:1–5`, `lib/json.id:1–13`, `lib/sqlite.id:1–4`, `lib/pipeline.id:1–12`, `lib/meta.id:1–4`, `lib/proof/tac.id` (all lines are comment-led), `lib/compiler/emit_c.id:1–24`, `tools/wasm/src/engine.id`, `tools/wasm/bench/*.id`.
- Note: `#` is confirmed as the comment marker by the std-zero-ledger counting rule (`docs/spec/std-zero-ledger.json`: "`#` line comment") and by `idol check` accepting `#` comments (exit 0, probe 2026-09-11).
- **Fix:** strip all `#` comments from `.id` files. **Sequences after:** #3 (checker must reject `#`, otherwise stripped comments regress).

### #2 — Real-time cross-device via one canonical surface. VIOLATED.
- The live multi-device system does not go through one canonical surface. Evidence:
  - 37 ad-hoc scripts in `/Users/clp/.hermes/scripts/` (outside the repo): `idol_live_adaptive_routing.py`, `idol_live_semantic_cache.py`, `idol_live_gateway_tick.py` (+2 `.bak`), `idol_live_bounded_dispatch.py` (+2 `.bak`), `idol_live_fleet_tick.py`, `idol_live_chain_monitor.py`, `idol_telegram_status.py`, `idol-live-fleet-saturation.sh`, `run-saturation-wave.sh`, etc.
  - In-repo: `coord/cron/*.sh` (`lane.sh`, `overnight.sh`, `healthcheck.sh`, `migrate-private-prefixes.sh`, `filter_pending.py`), `bin/idol-main-mcp.sh`, `scripts/live/reconcile.sh`.
  - In-repo `channels/` and `subscriptions/` directories exist but are **empty** — the intended surface has no implementation.
- **Fix:** define the single canonical surface (likely the MCP/kanban event surface), reimplement the 37 scripts' behavior as Idol behind it, delete the sprawl. **Sequences after:** #8 (shell/python removal), #15 (Idol-native implementations), and the L6/L7 feasibility work below.

### #3 — Idolic violations must be IMPOSSIBLE (reject, not warn). VIOLATED — proven empirically.
- Probe with built compiler `zig-out/bin/idol` (2026-09-09 build), throwaway files in `/tmp`:
  - `my_var = 1` → `idol check` → exit 0, "✓ checked — no errors"
  - `myVar = 1` → exit 0, "✓ checked — no errors"
  - `# comment` → exit 0, "✓ checked — no errors"
- So underscores, camelCase, and comments are all *accepted*. The constitution (`docs/spec/constitution.md:1046`: "`syntax.name` denies underscore and uppercase"; `:321`: snake_case/camelCase/etc. "forbidden") is not enforced by the checker.
- `gate/*.sh` vocabulary gates exist but are shell scripts (themselves #8 violations) and advisory; the bench commit `85886ee3` notes "Idol programs excluded by vocabulary gate", i.e. the gate *excludes* rather than *rejects*.
- **Fix:** implement hard errors (non-zero exit, no artifact) in the checker for: `#` comments, `_` in identifiers, uppercase in identifiers, mashed compounds. **This is the #0 enabler — it must land before #1, #4, #5, #9 refactors, or they cannot be verified.**

### #4 — No underscores anywhere ever; no mashed compound words. VIOLATED.
- **Filenames:** 898 tracked files contain `_` (excluding `.zig-cache`, `bench/verify/.work` artifacts). Includes `.agents/*_*.md`, `bench/platforms/x86_64-*.sh`, `benchmarks/wasm_*`, and hundreds under `benchmarks/wasm_rt/`, `test/`, `tools/`.
- **Identifiers in `lib/` `.id`** (top by occurrence): `int64_t`×244, `read_i64`×215, `write_i64`×215, `write_byte`×119, `uleb_end`×116, `uleb_val`×106, `hidden_size`×101, `read_byte`×94, `fn_ref`×82, `head_dim`×70, `compile_fail`×69, `uint8_t`×68, `fd_write`×62, `seq_len`×60, `peek_char`×60, `max_val`×59, `size_t`×57, `token_view`×57, `FNV_PRIME`×57, `lua_Value`×55, `type_name`×53, `uint64_t`×51, `native_differential`×51, `host_functions`×50, `__emit`×50, `str_join`×48, `fs_exists`×47, `register_import`×46, `reader_u8`×46, `make_concept`×46. (Some are C-FFI spellings, e.g. `sqlite3_open` in `lib/sqlite.id`, `nByte`/`pzTail` — the FFI boundary needs an explicit policy.)
- **Mashed/abbreviated compounds** (two words jammed into one lowercase token, forbidden by LAW-ONE per `constitution.md:587`): `lib/compiler/native.id` — `wjmp`, `wrl`, `wrr`, `wind`, `wcd`, `wopen`, `purecount`, `hassub`, `mulred`, `simpadd`, `simpmul`, `foldop`, `movz`, `movk`, `addsh`, `bcond`, `powtwo`; `lib/meta.id` — `getmetatable`, `std_meta_typeof`, `make_concept`; filenames `nativespliceprobe.id`, `splicetableprobe.id`.
- **Fix:** rename to canonical `subject:edge` form; rename files. **Sequences after:** #3.

### #5 — No camelcase; no names decomposable to an existing graph edge. VIOLATED.
- camelCase identifiers in 30+ `lib/` files: `macOS`×20, `commaSep1`×19, `findFunc`×16, `commaSep`×14, `inputSchema`×13, `zA`×12, `tryLowerSubjectRelationEdgeCall`×8, `tableShapeEntity`×8, `hasDescriptorFacts`×8, `nByte`×7, `findTableShape`×7, `entitiesOfKind`×7, `applicationRelation`×6, `hasField`×6, `classifyDescriptorRecursionFromEdges`×6, `applicationArguments`×5, `functionsInModule`×5, `findEnumShape`×5, `findByNameOfKind`×5, `findByName`×5, `classifyDescriptorRecursion`×5, `applicationsIn`×5, `applicationSubject`×5, `addEdge`×5, `resolveTableShapeType`×4, `resolveInHome`×4. Files include `lib/compiler/parser.id`, `lib/compiler/lexer.id`, `lib/compiler/token.id`, `lib/compiler/symbol.id`, `lib/compiler/record.id`, `lib/compiler/application.id`, `lib/json.id`, `lib/mcp.id`, `lib/sqlite.id`, `lib/net.id`, `lib/crypto.id`, `lib/jit.id`, `lib/build.id`, `lib/strconv.id`, `lib/strings.id`.
- **Fix:** lowercase single words; where a name decomposes to an existing edge, use the edge (see #9). **Sequences after:** #3.

### #6 — Faster than fastest oracles, proven. VIOLATED (owned by fixes workstream — do not touch).
- `bench/RESULTS.md`, generated 2026-09-11T22:18:37 by `bench/run.sh` (21 interleaved rounds, 3 warmup, median primary):
  - `sum`: idol 0.027992s vs clang 0.002259s → **loss, −1138.88%**, p=0.0000
  - `arith`: idol 0.054334s vs clang 0.041590s → **loss, −30.64%**, p=0.0003
  - `fib`: idol 0.001918s vs clang 0.001900s → loss, −0.93%, p=0.2802 (n.s.)
  - (Consolation, not the spec: compile time idol 0.023–0.025s beats clang 0.038–0.039s; object size 279–303 bytes beats clang's 512–544.)
- The honest-loss reporting is good practice; the spec demands wins. The 7 performance fixes target exactly this.
- **Fix:** owned by fixes agent. **Audit role:** none — record only. Spec refactors (#15 etc.) must not regress these numbers; re-run `bench/run.sh` after each refactor phase.

### #7 — Preserve intent: `.1 + .2 == .3`. VIOLATED.
- **v5 path:** the subset has no decimal literals at all. `lib/compiler/native.id` `num()` (lines 66–72) parses ASCII digits only; a `.1` token fails the `digit(t:byte(1))` test and falls through to `reg(names, t)` (variable lookup) — silent miscompilation risk, not even a clean error.
- **Full path:** `idol run` on `x = .1 + .2 / print(x == .3)` fails at compile time: `error: wasm32-wasi: no native realization (UnsupportedProgram)` / `hint: refused at: print_value/f64-slot-in-integer-position`. The program cannot be evaluated, correctly or otherwise, on the default target.
- The *spec* is right (`docs/spec/numerics.md`: "An unqualified numeric literal preserves its exact mathematical information until context and demand require an observable numeric law"), the implementation is absent.
- **Fix:** (a) v5: decide whether the subset gains decimal literals with exact decimal semantics, or documents exclusion; (b) full path: implement f64/decimal realization on default targets. Note `lib/live/route.id` already uses the fixed-point idiom (`done * 1000000 // total // p`) as a workaround — standardize it. **Sequences after:** numeric design decision; independent of #15 but should precede any #15 rewrite of numeric code.

### #8 — No shell/python IN THE REPO. VIOLATED.
- Tracked files: **147 `.sh`** + **11 `.py`** = 158. Highlights: `bench/run.sh`, `bench/timing.py`, `bench/verify/*.py` (9 files), `tools/wasm/proof.sh`, `tools/concept/*.sh` (12), `coord/cron/*.sh` + `filter_pending.py`, `gate/*.sh` (~20), `bin/idol-main-mcp.sh`, `scripts/test_gap221.sh`, `scripts/live/reconcile.sh`, `test/pecoffarm.sh`, `examples/cbackend/prove.sh`, `benchmarks/wasm_rt/perf/*.py` (4), `gate/outcome.py`, `test/pecoffx86/check.py`, `test/proofdata/chain.py`.
- **Embedded shell in Idol:** 15 `lib/` files call `os.execute`/`io.popen`: `lib/script.id`, `lib/compress/gzip.id`, `lib/net/smtp.id`, `lib/fs_watch.id`, `lib/mproc.id`, `lib/zip.id`, `lib/io/util.id`, `lib/process.id`, `lib/math/prng.id`, `lib/fs.id`, `lib/net.id`, `lib/tar.id`, `lib/ml/device.id`, `lib/runtime.id`, `lib/os/process.id` (e.g. `lib/mproc.id:23`: `io.popen(cmd .. " 2>&1 & echo $!", "r")`).
- **Fix:** reimplement load-bearing harnesses in Idol, then delete. **Critical sequencing:** `bench/run.sh` + `bench/timing.py` + `tools/wasm/proof.sh` are load-bearing for the fixes workstream — **do not remove until the 7 fixes ship and their replacements are proven**. Deletion is the last step of the spec program, not the first.

### #9 — Names decomposable to existing graph edges MUST be decomposed. VIOLATED.
- `lib/script.id:233` `fs_exists` → `fs:exists`; `lib/script.id:419,431` re-export it twice more.
- `lib/schema_gen.id:15`, `lib/rewrite.id:15`, `lib/pipeline.id` `str_join` → `str:join` (the `str` table + `join` edge already exist as concepts).
- `lib/meta.id:131` `make_concept` → `make:concept`; `lib/meta.id:903–904` re-exports.
- `read_i64`/`write_i64`/`read_byte`/`write_byte`/`peek_char` (in `lib/mem.id`, `lib/wasm/decode.id`, `tools/wasm/src/engine.id`) → `read:i64`, `write:byte`, etc.
- `token_view`×57, `register_import`×46, `reader_u8`×46, `type_name`×53, `native_differential`×51, `host_functions`×50, `compile_fail`×69.
- **Fix:** decompose to `subject:edge(rest)`; canonicalize on existing edges. **Sequences after:** #3 (checker), and needs the edge-vocabulary authority (GAP-124 graph obligations) to decide canonical edges.

### #10 — Folder info in deterministic runtime/meta graph, no loose files. VIOLATED.
- No in-repo mechanism captures folder membership as a deterministic graph. `lib/meta.id` (997 lines) covers type reflection only; no folder projection found.
- Loose/unclaimed: `channels/` and `subscriptions/` are empty directories with no owning table or manifest; `.agents/census/zerohistory.baseline` is a single integer (`7439`), not a graph.
- **Fix:** folder→table projection in the meta graph (every directory's membership enumerated deterministically); delete or claim empty dirs. Independent track; can proceed early.

### #11 — No blockers. VIOLATED.
- **125 open GAP files** under `gaps/` (of 170 total), e.g. `GAP-025`, `GAP-030`, `GAP-149` (numeric descriptor facts), `GAP-157` (STD-ZERO, owns the std ledger), `GAP-124` (graph obligations for world authority), `GAP-220`.
- The spec program cannot complete while blockers stand; several are prerequisites (GAP-124 for #9 edge authority, GAP-157 for #12, GAP-149 for #7).
- **Fix:** triage; close or re-scope. Sequenced throughout — GAP-124/GAP-149/GAP-157 are on the critical path.

### #12 — No bloated stdlib. VIOLATED.
- `lib/` holds **277 `.id` files in 31 subdirectories** — crypto, tls, aes, hmac, onnx, autodiff, graphics/shader, wasm/jit, mcp, smtp, tar, zip, toml, yaml, ini, csv… — far beyond a minimal stdlib.
- Duplicates/overlaps: `str.id` / `string.id` / `strings.id`; `db.id` / `database/`; `math.id` / `math/`; `time.id` / `time/`; `table.id` / tables in `collections.id`; `token/` dir with no `token.id`.
- `docs/spec/world.md` "STD-ZERO / LIB-ZERO": "No canonical `std.*` or `lib.*` semantic hop. Repository `lib/` path is bootstrap provenance only." Yet `docs/spec/std-zero-ledger.json` measures **350 code-position `std.` sites across 94 files**, and `lib/meta.id` itself defines `std_meta_typeof` — the stdlib is load-bearing, not provenance-only.
- **Fix:** per GAP-157: shrink to the proven-minimal surface; the rest moves out of the canonical tree or is deleted. **Sequences after:** #15 (rewrites may change what the stdlib needs to provide) and GAP-157.

### #13 — Proof assistant = programming language (unified). VIOLATED.
- Proving today is: `tools/wasm/proof.sh` (shell; bootstraps zig from a pinned tarball, clones the `wart` oracle repo, builds it, and on non-Darwin hosts runs `idol dump-c` + `cc -std=c11 -O2`) driving `tools/wasm/test/conform.id` against external `wasmtime` and `wart` binaries. The proof *assistant* is shell + Zig + C + two external oracles.
- `lib/proof/` (`check.id` 103 lines, `prop.id` 34, `tac.id` 110) is string-manipulation helpers for proof-shaped text, not a proof assistant. `idol prove` is a Zig subcommand.
- Counter-signal: `docs/design/proofunity.md` (committed today, `f175bb5c`) specs phase-1 kernel unification — the design exists, the implementation does not.
- **Fix:** implement the proofunity kernel in Idol per that doc; retire `proof.sh`'s shell/cc/oracle path. **Sequences after:** #8 (proof.sh removal) and #14 (cc removal).

### #14 — No intermediaries (no C/assembler/linker in final path). VIOLATED.
- `lib/compiler/emit_c.id:1–24` header: "**SH-10 is the row the plan calls 'canonical path today'**" and documents the path `Duo source -> emit_c -> cc -> ./a.out -> exit code`. The C backend is the canonical path today by its own admission (kept as differential-test backend).
- `lib/pipeline.id:1–12` header: "Chains of map/filter/reduce/collect are analyzed at compile time and fused into a single, **allocation-free C loop**" via `@c.emit`; `fuse_reduce` etc. generate C source strings (`lib/pipeline.id:38,55`).
- `lib/mem.id:176`: `@comp.c.emit([[({ lua_Value _v; … malloc … })]])` — inline C in family code.
- `lib/jit.id:46`: `if (mprotect(p, (size_t)n, PROT_READ | PROT_EXEC) != 0) return -1;` — C code in `.id`.
- 631 `.c` files under `src`/`lib`/`tools`/`bench` (includes `tools/wasm/src/duo_keyword_classify.c`).
- `tools/wasm/proof.sh`: `cc_bin=${CC:-cc}; "$cc_bin" -std=c11 -O2 -o "$out" "$out.c" -lm` on non-Darwin hosts.
- The v5 `native.id` path itself (`.id` → arm64 Mach-O bytes, no assembler/linker) is the compliant shape — the violations are the *other* backends and escape hatches around it.
- **Fix:** demote `emit_c` to explicit, non-canonical bootstrap differential only; remove `@c.emit`/`@comp.c.emit` from `pipeline.id`/`mem.id`; rewrite `jit.id` without C; replace `proof.sh`'s `dump-c`+`cc` path with the direct native backend. **Sequences after:** #15 (pipeline/mem rewrites) and the fixes workstream (do not disturb `native.id`).

### #15 — Idol-native ways MANDATORY in Idol's own code. VIOLATED. (Bootstrapping analysis below.)
- `while`: 170/277 `lib/` files. `if`: 248/277. `for`: 211/277.
- `lib/compiler/native.id` (555 lines): 20+ `while` loops (lines 19, 57, 75, 88, 109, 122, 148, 165, 196, 231, 247, 277, 287, 296, 326, 340, 353, 370, 392, 407, 422, 439) and 40+ `if`s — string scanning, the main parse loop, and the while-loop stack are all imperative.
- Even the newest spec-shaped code violates it: `lib/live/route.id` and `lib/live/cache.id` (the L6/L7 Idol specs) use `if`/`while` throughout.
- `lib/pipeline.id` `str_join` uses `for i, part in parts` — then generates C `for` loops as strings.
- `lib/fn.id`/`lib/iter.id` provide `map`/`filter`/`foldl`/`foldr` as *library* functions, but each is implemented with `while`+`if` internally (`lib/fn.id:15–24`, `lib/iter.id:9–20`). The functional surface exists; the primitive does not.

### #16 — Compact operators (`and`/`or`/`not`). VIOLATED.
- `!` used as `not` in Idol code: `lib/script.id:32` (`if !ok(cmd)`), `lib/proof/tac.id:60` (`if !u:check(h:ctx(), h:prop())`), `lib/compiler/parser.id:312` (`if !lx.has_error`).
- `&&`/`||` inside generated logic strings: `lib/contracts.id:78` (`str_join(parts, " && ")`), `:80` (`"(!(" .. antecedent .. ") || (" .. consequent .. "))"`), `:82`. (Inside strings, but they generate non-Idol logic text — flag for the #15 rewrite.)
- `lib/mem.id`, `lib/jit.id`, `lib/target/arm64.id` `&&`/`||` occurrences are inside embedded C or opcode tables, covered by #14.
- **Fix:** `!x` → `not x` everywhere in `.id` code; can ride along with the #15 rewrite.

### #17 — NEVER sentinels. VIOLATED.
- `lib/compiler/native.id:61` (`powtwo`: `return 0 - 1`), `:69` (`0 - 1`), `:134` (`find`: `0 - 1`), `:463` (`if find(names, name) == 0 - 1` — sentinel *comparison*).
- `lib/slices.id:56,66` (`return 0 - 1`), `lib/sort.id:157`, `lib/compiler/emit_c.id:106,113,127`, `lib/compiler/lexer.id:830,845` (`return 0 - 100 - lex.error_code`), `lib/meta.id:278–284` (`return -1` comparators), `lib/jit.id:46` (C `!= 0`).
- `lib/json.id` header documents a "Sentinel that encodes as `{}`" — a self-aware violation.
- **Fix:** replace with option/nil-or-error returns. Note the tension: v5 has no nil/option type — sentinel removal in `native.id` needs either an explicit error channel or a pre-agreed out-of-band signal that is *not* a sentinel value in the value domain. Decide in the #15 design. **Sequences with #15.**

### #18 — Familiar faces for user interop, NEVER in family code. VIOLATED (family-code half).
- User-interop half is correctly preserved: `native.id` parses and compiles user `while` (lines ~380–420 emit real loop code); `bench/programs/*.id` are user programs.
- Family-code half violated: identical corpus to #15. Every `while`/`if`/`for` cited in #15 is an #18 violation too.
- **Fix:** same rewrite as #15. The user-facing grammar keeps `while`; the family implementation must not use it.

### #19 — Files are table scope; `M = ; M` inventory; table layout. VIOLATED (layout half).
- **Inventory — the `M = ; M` implicit-return pattern** (file builds table `M`, returns it bare): 38 files end with a bare `M`, e.g. `lib/color.id` (`global M = {}` … trailing `M`), `lib/pipeline.id`, `lib/math.id`, `lib/mcp.id`, `lib/regex.id`, `lib/result.id`, `lib/rewrite.id`, `lib/schema_gen.id`, `lib/ffi_gen.id`, `lib/string.id`, `lib/strings.id`, `lib/term.id`, `lib/foreign.id`, `lib/contracts.id`. No literal `M = ; M` with a semicolon exists anywhere in `.id` (the semicolon is correctly denied — cf. `gate/path.id:655–664` test strings).
- **Layout violations** — directories without root `table.id` (10): `lib/compiler/`, `lib/compress/`, `lib/database/`, `lib/encoding/`, `lib/index/`, `lib/ml/`, `lib/target/`, `lib/testing/`, `lib/text/`, `lib/token/`. Plus `lib/live/` (no `live.id`) though `lib/live/route.id` and `lib/live/cache.id` exist.
- Compliant examples: `lib/c.id`+`lib/c/`, `lib/crypto.id`+`lib/crypto/`, `lib/math.id`+`lib/math/`, `lib/net.id`+`lib/net/`, etc.
- **Fix:** add the 11 missing root `table.id` files (mechanical). Independent — can land any time after the perf fixes ship.

### #20 — Maximally performant, proven. VIOLATED.
- Same evidence as #6. Owned by the fixes workstream. The spec refactors must be performance-neutral-or-better; gate every phase on `bench/run.sh`.

## Critical analysis A — the #15 bootstrapping question

| # | directive |
|---|---|
| 1 | **Question:** does the current v5 subset even support chained/functional constructs? |
| 2 | If not, is implementing them a prerequisite? |

| # | directive |
|---|---|
| 1 | **Answer: No — and the prerequisite is subtler than "extend v5".** |

| # | directive |
|---|---|
| 1 | There are three distinct languages in play; conflating them is the trap: |

1. **v5-subset** (what `native.id` *compiles*): integers, assignments, `+ - * /`, `while`, `return`. Evidence: `bench/programs/arith.id` (flat assignments + one `while` + trailing expression); `native.id`'s parser only recognizes `<`, `=`, `+ - * /`, `while`, identifiers, integer literals. **No strings, no tables, no first-class functions, no method calls, no chained calls.** A chained/functional construct *cannot be expressed* in v5 — there is nothing to chain on.

2. **Full Idol** (what `native.id` is *written in*, compiled by the Zig `idol` binary): has chained calls (`s:byte(i)`, `t:sub(1,5)`, `stdin:read()`), higher-order functions (`fn_ref` parameters in `lib/fn.id`, `lib/iter.id`), `and`/`or`/`not`, `if`/`else`, `for`, `while`, tables, strings, nil. Chained/functional *surface* exists — but only as **library functions implemented imperatively** (`lib/fn.id:15–24` `foldl` is `while`+`if`; `lib/iter.id:9–20` `filter` is `while`+`if`). There is **no primitive** chained construct that compiles without `while`/`if` underneath.

3. **Duo** (the Lua-facing dialect several `lib/` files are written for — `lib/json.id`, `lib/mcp.id`, `lib/pipeline.id`, `lib/sqlite.id` headers say "for Duo"): its relationship to the 20-point spec is itself un-audited; several Duo-isms (`for k, _ in t`, `else(cond)`, `!=`, `!`) leak into what is supposed to be Idol family code.

| # | directive |
|---|---|
| 1 | **Therefore the #15 refactor of `native.id` does NOT require extending the v5 subset.** `native.id` is written in full Idol, and full Idol already has the *spelling* of chained/functional code. |
| 2 | What is missing is the **primitive**: either |

- **(a) a compiler-desugared chain construct** in the Zig full-Idol compiler (e.g. a pipeline operator or blessed `map`/`filter`/`fold` that lowers without `while`/`if`), or
- **(b) recursion + guaranteed tail-call optimization** as the canonical looping form, so every `while` becomes a self-call the compiler proves equivalent.

| # | directive |
|---|---|
| 1 | Without (a) or (b), rewriting `native.id`'s 20+ `while` loops "functionally" just pushes the `while` into `lib/fn.id` — which is exactly the current state and still violates #15/#18. **Decision (a)-vs-(b) is the prerequisite; it must land in the Zig compiler before any #15 refactor of `native.id` or `lib/` is possible.** The sibling workstream owns `native.id` — hand them this decision, do not preempt it. |

| # | directive |
|---|---|
| 1 | One more trap: `native.id` must *keep compiling user `while`* (#18 user-interop half). |
| 2 | The #15 rewrite changes only the compiler's *implementation language*, never the accepted *source language*. |

## Critical analysis B — L6/L7 Python bridges: Idol reimplementation feasibility

| # | directive |
|---|---|
| 1 | Targets: `/Users/clp/.hermes/scripts/idol_live_adaptive_routing.py` (168 lines, L6) and `idol_live_semantic_cache.py` (183 lines, L7). |

| # | directive |
|---|---|
| 1 | **What the scripts need:** SQLite (read + write), JSON (policy/state files), SHA-256, regex substitution, wall-clock time, filesystem paths, argv parsing, seeded RNG, stdout printing, floats (score = success/p50), sets/dicts/lists, sorting. |

| # | directive |
|---|---|
| 1 | **Can the v5 subset express this? |
| 2 | No.** Exact language gaps in v5: |

- **G1 — no strings.** SQL text, JSON text, file paths, fingerprints, and task text cannot be represented. v5 programs have no string literals or string values.
- **G2 — no floats.** L6's `score = success_rate / p50_latency` and L7's Jaccard `|∩|/|∪|` need fractions. (Workaround exists: `lib/live/route.id` already does fixed-point — `done * 1000000 // total // p` — so G2 is bridgeable by convention, not by language.)
- **G3 — no tables/lists/dicts/sets.** Provider-stat maps, task lists, cert sets, word sets have no representation.
- **G4 — no I/O, syscalls, time, argv, or RNG.** v5 programs cannot open the kanban DB, read the policy JSON, print, or seed randomness. (`native.id`'s `main` reads stdin, but v5 *user programs* have no I/O surface.)
- **G5 — no modules.** The bridge cannot be structured or imported.
- **G6 — single flat `main`.** v5 programs are assignment sequences; the scripts' ~10 functions each have no v5 analogue.

| # | directive |
|---|---|
| 1 | **Can full Idol express this? |
| 2 | Yes — the lib surface already exists,** but every dependency is itself spec-violating today: |

| Need | Idol lib | Status |
|---|---|---|
| SQLite | `lib/sqlite.id` | exists, but `@ffi("sqlite3_open")` → **C ABI** (see #14 tension below) |
| JSON | `lib/json.id` | exists ("Pure Duo"), needs #1/#15/#4 refactor |
| Regex | `lib/regex.id` | exists, needs refactor |
| SHA-256 | `lib/crypto/sha.id` | exists, needs refactor |
| RNG | `lib/random.id`, `lib/math/prng.id` | exist, `prng.id` uses `io.popen` (#8) |
| argv | `lib/argparse.id` | exists, needs refactor |
| fs/time | `lib/fs.id`, `lib/os.id`, `lib/time.id` | exist, `fs.id` uses `io.popen` (#8) |
| HTTP (if needed) | `lib/http.id` → `lib/net.id` | exists, `net.id` uses `io.popen` (#8) |

| # | directive |
|---|---|
| 1 | **Notable:** the pure scoring kernels are *already* reimplemented in v5-style Idol: `lib/live/route.id` (`score`, `pick`, `lcg`, `explore`, `routeopen` — fixed-point, integer-only) and `lib/live/cache.id` (`fpeq`, `near`, `wasted`, `popcount`). |
| 2 | These two files are the correct nucleus — but they too use `if`/`while` (#15) and `lib/live/` lacks `live.id` (#19). |

| # | directive |
|---|---|
| 1 | **Feasibility verdict:** feasible in **full Idol only**, not in v5. |
| 2 | Prerequisites, in order: |

1. #15 decision (analysis A) — the bridge's loops must be expressible functionally.
2. Refactor `lib/sqlite.id`, `lib/json.id`, `lib/regex.id`, `lib/crypto/sha.id`, `lib/random.id`, `lib/argparse.id`, `lib/fs.id` to spec (#1, #4, #15).
3. Resolve the **#14 tension**: `lib/sqlite.id` binds `libsqlite3` via C FFI. Either the spec blesses a pure-Idol SQLite (large work) or it admits FFI as a non-"final path" boundary with an explicit policy. Until decided, the Idol bridge still routes through C.
4. Then write `lib/live/adaptive.id` + `lib/live/cache.id` (full versions) against those modules, and retire the two `.py` bridges (they live outside the repo, so this is addition, not deletion — no #8 conflict).

## Recommended refactor order (after the 7 performance fixes ship)

| # | directive |
|---|---|
| 1 | **Phase 0 — unblock, do not disturb.** |

- 0a. Fixes workstream ships; `bench/RESULTS.md` shows wins. Re-run `bench/run.sh` before and after every phase below.
- 0b. **Decide the #15 primitive** (analysis A, option (a) vs (b)) and implement it in the Zig full-Idol compiler. Nothing in #15 can start without this.
- 0c. Triage GAP-124 (edge authority for #9), GAP-149 (numerics for #7), GAP-157 (STD-ZERO for #12) — they gate later phases.

| # | directive |
|---|---|
| 1 | **Phase 1 — checker (#3).** Make `idol check` reject (non-zero, no artifact): `#` comments, `_`/uppercase identifiers, mashed compounds. |
| 2 | This is the enforcement prerequisite for #1, #4, #5, #9. |

| # | directive |
|---|---|
| 1 | **Phase 2 — mechanical deletions/renames.** |

- #1: strip `#` comments from all `.id` (verifiable by Phase-1 checker).
- #19: add the 11 missing root `table.id` files (`lib/compiler/`, `lib/compress/`, `lib/database/`, `lib/encoding/`, `lib/index/`, `lib/ml/`, `lib/target/`, `lib/testing/`, `lib/text/`, `lib/token/`, `lib/live/`).
- #4/#5/#9: identifier + filename renames to `subject:edge` canonical form (needs GAP-124 edge authority for #9).

| # | directive |
|---|---|
| 1 | **Phase 3 — family-code rewrite (#15/#18, with #16/#17 riding along).** Rewrite `while`/`if`/`for` out of `lib/` and `native.id` using the Phase-0b primitive; `!` → `not`; sentinels → option/error returns (needs the v5 error-channel decision for `native.id`). |
| 2 | Coordinate with the sibling workstream: they own `native.id`; sequence their perf fixes first, then the #15 rewrite, then re-bench. |

| # | directive |
|---|---|
| 1 | **Phase 4 — backend purity (#14) and proof unity (#13).** Demote `emit_c` to explicit bootstrap-differential; remove `@c.emit` from `pipeline.id`/`mem.id`; de-C `jit.id`; replace `proof.sh`'s `dump-c`+`cc` path with the direct backend; implement the `docs/design/proofunity.md` kernel in Idol. |

| # | directive |
|---|---|
| 1 | **Phase 5 — surface consolidation (#2, #8, #10, #12).** Reimplement the 37 `~/.hermes/scripts` behaviors + `coord/cron` + `scripts/live` as Idol behind the single canonical surface; full L6/L7 Idol bridges per analysis B; folder→table meta graph; stdlib slimming per GAP-157/STD-ZERO. **Delete the 158 `.sh`/`.py` files only after their Idol replacements are proven** — `bench/run.sh`, `bench/timing.py`, `tools/wasm/proof.sh` last. |

| # | directive |
|---|---|
| 1 | **Phase 6 — numerics (#7) and blockers (#11).** Decimal-literal design (v5 inclusion vs documented exclusion; full-path f64 realization fix); close the remaining GAPs. |

| # | directive |
|---|---|
| 1 | **Continuous:** #6/#20 — every phase re-runs `bench/run.sh`; any regression is a stop-ship for that phase. |
