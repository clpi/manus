const std = @import("std");

/// SH-02 + SH-03 production seam. These travel together: any module that
/// reaches `duo_lexer_bridge` reaches both the keyword table and the Duo lexer
/// behind it, so linking them separately only produces undefined symbols later.
///
/// The Duo lexer artifact also defines a STRONG `duo_keyword_classify`, which
/// overrides the weak one in src/duo_keyword_classify.c — that file was written
/// weak for exactly this case.
fn linkProductionKeywordClassify(b: *std.Build, mod: *std.Build.Module) void {
    // src/duo_keyword_classify.c retired 2026-08-07: it declared
    // duo_keyword_classify `weak` precisely so a full Duo artifact could
    // override it, and src/duo_lexer_tokenize.c now provides the strong
    // definition (both are generated from lib/std/token/classify.duo, so this
    // is one source of truth, not two). Its ledger deletion gate — "delete once
    // nothing links the weak fallback" — is met.
    linkProductionDuoLexer(b, mod);
    mod.link_libc = true;
}

/// SH-03 production dispatch: the Duo lexer, generated from
/// lib/std/compiler/host.duo. Provides duo_lexer_tokenize_full and friends for
/// src/duo_lexer_dispatch.zig, and a STRONG duo_keyword_classify that overrides
/// the weak one above — which is why that one is weak.
fn linkProductionDuoLexer(b: *std.Build, mod: *std.Build.Module) void {
    mod.addCSourceFile(.{
        .file = b.path("src/duo_lexer_tokenize.c"),
        .flags = &.{ "-std=c11", "-w" },
    });
    mod.link_libc = true;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "duo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    linkProductionKeywordClassify(b, exe.root_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (@hasDecl(std.Build.Step.Run, "addPassthruArgs")) {
        run_cmd.addPassthruArgs();
    } else {
        run_cmd.addArgs(b.args orelse &.{});
    }

    const run_step = b.step("run", "Run duo");
    run_step.dependOn(&run_cmd.step);

    const test_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_compile_fail_tests.duo" });
    test_cmd.setCwd(b.path("."));
    test_cmd.step.dependOn(b.getInstallStep());
    // G11 — the language census ratchet. A number nobody runs is a number that
    // drifts, which is how "no language but Duo" stayed a slogan instead of a
    // list of twelve files.
    const census_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/language_census.duo" });
    census_cmd.setCwd(b.path("."));
    census_cmd.step.dependOn(b.getInstallStep());
    const census_step = b.step("language-census", "G11: count tracked non-Duo source; ratchets sh/py, js and zig");
    census_step.dependOn(&census_cmd.step);

    // U8 -- Pass 105 section 4's `toolchain@{ foreign = ledger | oracle }`. The
    // step above answers how MUCH foreign code there is; this one answers by
    // what RIGHT each file is here. Two licences exist -- bootstrap ledger with
    // a termination condition (Pass 103 section 7), or CI oracle (section 5) --
    // and anything else is a violation. Rules live in docs/spec/foreign.md, the
    // same no-silent-default mechanism corpus.md uses for .duo.
    const foreign_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/foreign_census.duo" });
    foreign_cmd.setCwd(b.path("."));
    foreign_cmd.step.dependOn(b.getInstallStep());
    const foreign_step = b.step("foreign-census", "Pass 105 U8: every foreign file classified ledger or oracle; ratchets violations");
    foreign_step.dependOn(&foreign_cmd.step);

    // The native census. Same reasoning as G11 one level down: "native 100%"
    // was a slogan because nothing measured it honestly. `duo compile` falls
    // back to the C backend and still reports ok, so only --backend=direct is
    // an answer -- and the ratio has to be over the REACHABLE set, because a
    // compiler proof fixture that exists to drive the C emitter can never be
    // native and counting it turns a 90% ceiling into a 61% failure.
    const native_census_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/native_census.duo" });
    native_census_cmd.setCwd(b.path("."));
    native_census_cmd.step.dependOn(b.getInstallStep());
    const native_census_step = b.step("native-census", "native coverage over the reachable set; ratchets NATIVE_FLOOR");
    native_census_step.dependOn(&native_census_cmd.step);

    // The ABI shape matrix. The native differential judges the programs someone
    // wrote; this one judges GENERATED call shapes, because a corpus grows by
    // accident and an argument classifier is exactly the code that is right for
    // the shapes you tested and wrong for the rest. It was added after the
    // differential sat green at 81/2 over a backend that passed f64 arguments
    // in GP registers (gap[056]) — no corpus program had the shape, so the gate
    // was reporting corpus coverage and reading as correctness.
    //
    // MISCOMPILE_CEILING ratchets DOWNWARD, the mirror of NATIVE_FLOOR: a new
    // wrong answer fails, and fixing one should lower the ceiling in the same
    // commit or the gate goes slack.
    const abi_matrix_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/abi_matrix.duo" });
    abi_matrix_cmd.setCwd(b.path("."));
    abi_matrix_cmd.step.dependOn(b.getInstallStep());
    const abi_matrix_step = b.step("abi-matrix", "differential generated ABI call shapes; ratchets MISCOMPILE_CEILING down");
    abi_matrix_step.dependOn(&abi_matrix_cmd.step);

    // Pass 104 G-D3, the encode half. `abi-matrix` above is a G-D3-shaped gate
    // one level up -- generated shapes, oracle-checked, per row -- and Pass 104
    // §6 names it as the precedent to extend downward: "Generating ISA property
    // tests per instruction is the same move one level down."
    //
    // `lib/std/target/arm64.duo` is the instruction set as DATA (Pass 103 §2):
    // 45 forms, each a base word plus `field@hi:lo` layout facts, with ONE
    // derived encoder over all of them and no per-instruction code. This step
    // expands every row into 16 operand tuples, hands the assembler text to
    // clang, disassembles the object, and compares 720 words byte for byte. The
    // oracle is the external assembler and never this repository's own encoder
    // -- a generated test that agrees with a wrong descriptor proves nothing.
    //
    // It found two on its first run: `rbit` was the 32-bit form under a ctz
    // lowering that needs 64 (`@ctz(8)` answered 35 natively, 3 in C), and
    // `scvtf` converted from a 32-bit GPR while both callers pass an x
    // register. The gate carries three damaged descriptors as positive controls
    // and exits 3 -- not 0 -- if any of them goes uncaught.
    const isa_fidelity_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/isa_fidelity.duo" });
    isa_fidelity_cmd.setCwd(b.path("."));
    isa_fidelity_cmd.step.dependOn(b.getInstallStep());
    const isa_fidelity_step = b.step("isa-fidelity", "Pass 104 G-D3: ARM64 descriptors encode what the oracle assembler encodes");
    isa_fidelity_step.dependOn(&isa_fidelity_cmd.step);

    // Pass 100 §22's capability matrix. §22 answered "what works?" with a
    // Boolean and, for running, with "nothing" -- conservative rather than
    // honest, because a compiler does not implement a program, it carries it
    // some distance up a ladder and the distance is the information. This
    // reports the population of examples/ at each rung from described through
    // canonical. It depends on the install step for the same reason the census
    // does: a matrix measured with yesterday's compiler is a confident report
    // about a build nobody has, and the script refuses to run against one.
    const capability_matrix_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/capability_matrix.duo" });
    capability_matrix_cmd.setCwd(b.path("."));
    capability_matrix_cmd.step.dependOn(b.getInstallStep());
    const capability_matrix_step = b.step("capability-matrix", "Pass 100 §22: population of examples/ per capability rung");
    capability_matrix_step.dependOn(&capability_matrix_cmd.step);

    // The third §22 report, and the one review actually asks for. The other two
    // are POPULATION reports -- how far does the corpus get, how far does each
    // FIXTURE get -- and neither can answer "does THIS capability work", because
    // one capability takes several files and one file carries several
    // capabilities. This puts capabilities down the side and the §22 pipeline
    // across the top (described / parsed / semantic / graph / C / native /
    // witnessed / hosted), derives every cell by running the fixtures, and
    // prints `—` plus a NO FIXTURE line for any capability nothing demonstrates.
    // It carries its own positive controls: three damaged copies of a corpus
    // fixture must lose exactly one column each, or the report exits 3 rather
    // than printing a table it has not earned.
    const capability_rows_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/capability_rows.duo" });
    capability_rows_cmd.setCwd(b.path("."));
    capability_rows_cmd.step.dependOn(b.getInstallStep());
    const capability_rows_step = b.step("capability-rows", "Pass 100 §22: per-CAPABILITY matrix, generated from fixtures");
    capability_rows_step.dependOn(&capability_rows_cmd.step);

    // ward against wart, wasmtime and wasmer on one corpus, five axes. Before
    // this step nothing in the tree measured ward against anything but ward,
    // so "ward is faster" was an unmade claim rather than a weak one.
    //
    // Not part of `test` or `agent-smoke`, on purpose: it spawns roughly 300
    // processes and one workload alone runs four seconds, so it is a step you
    // ask for. It also does NOT build ward -- a benchmark that builds its own
    // subject reports the build -- and it prints the binary's timestamp plus a
    // warning when ward's source is dirty, so a stale measurement announces
    // itself instead of being quoted.
    //
    // What makes it fail is a REGRESSION against the baselines recorded in the
    // script, not a loss to another runtime. ward loses rows today and the
    // table ranks them; a gate that could only come out green would be
    // decoration, and this one is meant to produce a worklist.
    const runtime_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/runtime_bench.duo" });
    runtime_bench_cmd.setCwd(b.path("."));
    runtime_bench_cmd.step.dependOn(b.getInstallStep());
    const runtime_bench_step = b.step("runtime-bench", "ward vs wart/wasmtime/wasmer on loc, bytes, startup, rss and execution");
    runtime_bench_step.dependOn(&runtime_bench_cmd.step);

    const test_step = b.step("test", "Run all tests (unit + compile-fail)");
    test_step.dependOn(&test_cmd.step);

    // Zig unit tests (lexer, parser, AST, types, sema).
    // Run independently from the binary: `zig build unit-test`
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    linkProductionKeywordClassify(b, unit_tests.root_module);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
    const unit_test_step = b.step("unit-test", "Run Zig unit tests only");
    unit_test_step.dependOn(&run_unit_tests.step);

    const no_ansi_reports_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/assert_no_ansi_reports.duo" });
    no_ansi_reports_cmd.setCwd(b.path("."));
    no_ansi_reports_cmd.step.dependOn(b.getInstallStep());
    const no_ansi_reports_step = b.step("no-ansi-reports", "Assert report ANSI/no-color styling contract");
    no_ansi_reports_step.dependOn(&no_ansi_reports_cmd.step);
    const report_styling_step = b.step("report-styling", "Assert rich and no-color test report styling");
    report_styling_step.dependOn(&no_ansi_reports_cmd.step);
    test_step.dependOn(&no_ansi_reports_cmd.step);

    const gpu_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_gpu_benchmark.duo" });
    gpu_bench_cmd.setCwd(b.path("."));
    gpu_bench_cmd.step.dependOn(b.getInstallStep());
    const gpu_bench_step = b.step("gpu-bench", "Run Duo vs GPU Metal benchmark");
    gpu_bench_step.dependOn(&gpu_bench_cmd.step);
    test_step.dependOn(&gpu_bench_cmd.step);

    const bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_benchmark.duo" });
    bench_cmd.setCwd(b.path("."));
    bench_cmd.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run Duo vs C benchmark suite");
    bench_step.dependOn(&bench_cmd.step);

    const cross_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_cross_benchmark.duo" });
    cross_bench_cmd.setCwd(b.path("."));
    cross_bench_cmd.step.dependOn(b.getInstallStep());
    const cross_bench_step = b.step("cross-bench", "Run cross-language benchmark (Duo vs C vs Lua vs LuaJIT)");
    cross_bench_step.dependOn(&cross_bench_cmd.step);

    const wasm_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_wasm_benchmark.duo" });
    wasm_bench_cmd.setCwd(b.path("."));
    wasm_bench_cmd.step.dependOn(b.getInstallStep());
    const wasm_bench_step = b.step("wasm-bench", "Run WASM runtime benchmark (wasmtime, wazero, wasm3, iwasm, wasmer, spin)");
    wasm_bench_step.dependOn(&wasm_bench_cmd.step);

    // ── wasm conformance suite (tools/wasm) ─────────────────────────────────
    // The WASM runtime ships in the release, and until 2026-08-08 it had NO
    // test suite: `test/main.duo` required four modules that had been deleted
    // and did not parse, so the only checking was a benchmark harness's `-1`
    // filter. This step builds the engine and differences every fixture against
    // wasmtime BY VALUE, under both engines and both entry shapes, and refuses
    // to print a score until its own controls pass (exit 3).
    //
    // It used to live at `ext/ward/` and be called ward. It is not a separate
    // product any more -- it is duon's wasm capability, so it sits beside the
    // other toolchain parts that version-lock to the compiler (`tools/lsp`,
    // `tools/mcp`). `docs/wasm-integration.md` records why NOT `lib/std/wasm/`:
    // the engine is a program, `capability-scan` has zero slack on a
    // `lib/std/**` denominator, and `stdlib_embed_gate` requires every file
    // under `lib/std` to be `req`-able, which a program with a `main()` tail
    // is not.
    //
    // Both commands run with cwd = tools/wasm so `duo run`'s `.out` artifact
    // lands where that directory's .gitignore already covers it, and the
    // compiled engine goes outside the tree for the reason the same .gitignore
    // states: a stale binary sitting next to the source is this project's
    // oldest measurement bug.
    // Paths are relative to the CHILD's cwd (tools/wasm), which is what setCwd
    // establishes before exec. An absolute path via the build root would be
    // nicer to read, and the API for it has moved twice in zig master.
    const wasm_conform_bin = "../../zig-out/bin/wasm-conform";
    const duo_bin_path = "../../zig-out/bin/duo";
    const wasm_engine_cmd = b.addSystemCommand(&.{
        duo_bin_path,  "compile",     "src/engine.duo",
        "--backend=c", "--emit",      "exe",
        "-o",          wasm_conform_bin,
    });
    wasm_engine_cmd.setCwd(b.path("tools/wasm"));
    wasm_engine_cmd.step.dependOn(b.getInstallStep());
    const wasm_test_cmd = b.addSystemCommand(&.{ duo_bin_path, "run", "test/conform.duo" });
    wasm_test_cmd.setEnvironmentVariable("DUO_WASM_BIN", wasm_conform_bin);
    wasm_test_cmd.setCwd(b.path("tools/wasm"));
    wasm_test_cmd.step.dependOn(&wasm_engine_cmd.step);
    const wasm_test_step = b.step("wasm-test", "wasm conformance: every fixture, both engines, differenced against wasmtime");
    wasm_test_step.dependOn(&wasm_test_cmd.step);

    const ml_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_ml_benchmark.duo" });
    ml_bench_cmd.setCwd(b.path("."));
    ml_bench_cmd.step.dependOn(b.getInstallStep());
    const ml_bench_step = b.step("ml-bench", "Run ML benchmark suite (Duo vs C)");
    ml_bench_step.dependOn(&ml_bench_cmd.step);

    // `scripts/run_honest_benchmark.sh` does not exist and has not for some
    // time — the Duo port is tracked and the shell file is not, so this step
    // was invoking bash on a missing path. Repointed at the file that is there.
    const honest_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_honest_benchmark.duo" });
    honest_bench_cmd.setCwd(b.path("."));
    honest_bench_cmd.step.dependOn(b.getInstallStep());
    const honest_bench_step = b.step("honest-bench", "Run honest benchmark (no precomputation, runtime inputs)");
    honest_bench_step.dependOn(&honest_bench_cmd.step);

    const compile_size_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_compile_size_benchmark.duo" });
    compile_size_bench_cmd.setCwd(b.path("."));
    compile_size_bench_cmd.step.dependOn(b.getInstallStep());
    const compile_size_bench_step = b.step("compile-size-bench", "Track compile time and binary size vs C");
    compile_size_bench_step.dependOn(&compile_size_bench_cmd.step);

    // Public safety pre-scan (Pass 10 A19)
    const public_safety_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/public_safety_scan.duo" });
    public_safety_cmd.setCwd(b.path("."));
    const public_safety_step = b.step("public-safety", "Scan tracked files for secrets and personal paths (Pass 10 A19)");
    public_safety_step.dependOn(&public_safety_cmd.step);

    // Pass 57 A2 — one source, N projection targets, compared on a stdout
    // fingerprint rather than exit status alone. native-differential compares
    // only exit status (it sends stdout to /dev/null), so two backends that
    // print different answers "agree" there as long as both exit 0.
    const semantic_harness_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/semantic_harness.duo" });
    semantic_harness_cmd.setCwd(b.path("."));
    semantic_harness_cmd.step.dependOn(b.getInstallStep());
    const semantic_harness_step = b.step("semantic-harness", "Every projection target must agree on stdout, not just exit status (Pass 57 A2)");
    semantic_harness_step.dependOn(&semantic_harness_cmd.step);

    const repo_hygiene_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/repo_hygiene.duo" });
    repo_hygiene_cmd.setCwd(b.path("."));
    const repo_hygiene_step = b.step("repo-hygiene", "Pass 11 WP-12: forbidden root artifacts and tracked agent noise");
    repo_hygiene_step.dependOn(&repo_hygiene_cmd.step);

    // tree-sitter-coverage -- Pass 100 section 19's editor front-end, measured.
    // Runs the generator (failing if it exits non-zero, which the nvim setup
    // script used to swallow), parses every tracked .duo file, and ratchets off
    // a ceiling on UNRECOGNISED files. It positive-controls its own detector on
    // every run against a valid file and a deliberately broken one, because a
    // coverage counter that cannot fail reports a number that proves nothing.
    const ts_coverage_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/tree_sitter_coverage.duo" });
    ts_coverage_cmd.setCwd(b.path("."));
    const ts_coverage_step = b.step("tree-sitter-coverage", "tree-sitter generates, and recognises a ratcheted share of the .duo corpus (GAP-049)");
    ts_coverage_step.dependOn(&ts_coverage_cmd.step);

    // Pass 101 "the host": tree-sitter is "a generated grammar projection
    // (output, never authored)". ext/tree-sitter-duo/grammar.js is PARTLY
    // that now -- everything outside its @@residue markers is emitted by
    // scripts/treesitter_emit.duo. This step regenerates and fails unless the
    // result is byte-identical to the tracked file, which is the only thing
    // that separates a generated artifact from an authored one with a banner.
    // It also prints the authored residue line count, which is the number
    // GAP-049 is measured by.
    const ts_projection_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/treesitter_emit.duo" });
    ts_projection_cmd.setCwd(b.path("."));
    ts_projection_cmd.setEnvironmentVariable("TSEMIT_CHECK", "1");
    ts_projection_cmd.step.dependOn(b.getInstallStep());
    const ts_projection_step = b.step("treesitter-projection", "grammar.js regenerates byte-identically from scripts/treesitter_emit.duo (GAP-049)");
    ts_projection_step.dependOn(&ts_projection_cmd.step);

    // c-floor -- constitution section 47, the three laws that make C a
    // CANDIDATE rather than the ceiling, measured instead of asserted. Half the
    // rows read the `c_floor` block of `duo explain` (the plan) and half run
    // both backends and time them (the world); a row that disagrees is the
    // finding. It is a step of its own rather than a row inside audit100
    // because it COMPILES AND RUNS programs -- seconds, not milliseconds -- and
    // because a measured loss for the native lowering is a legitimate PASS here
    // (the floor working) while every audit100 row is a violation count.
    const cfloor_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/cfloor.duo" });
    cfloor_cmd.setCwd(b.path("."));
    cfloor_cmd.step.dependOn(b.getInstallStep());
    const cfloor_step = b.step("c-floor", "constitution §47: the C-equivalent realization is a costed candidate; plan vs measurement");
    cfloor_step.dependOn(&cfloor_cmd.step);

    // audit100 -- CLAUDE.md section 1's deny table, executable. It scans the
    // canonical partition of docs/spec/corpus.md only, because compile_fail
    // fixtures are SUPPOSED to contain the denied text, and it ratchets off
    // measured budgets rather than gating at zero, because a gate that is red
    // on the day it ships is a gate people learn to skip.
    const audit100_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/audit100.duo" });
    audit100_cmd.setCwd(b.path("."));
    audit100_cmd.step.dependOn(b.getInstallStep());
    const audit100_step = b.step("audit100", "Pass 100 deny table over the canonical .duo corpus; ratchets each row");
    audit100_step.dependOn(&audit100_cmd.step);

    // role-scan is GONE, and this note is here so the next reader does not go
    // looking for it. gaps/GAP-078.md: two role taxonomies landed in this tree
    // on the same day and disagreed -- on `:`, on the count, on whether an
    // ordinary binding has a hue, on the spelling of the string role, and on
    // whether the section 0g fine splits are roles. Two generators for one
    // legend means whichever a front end picks, the other convicts it, and the
    // two coverage numbers measured different quantities. The ruling merged
    // them into ONE taxonomy and DELETED `scripts/role_scan.duo` rather than
    // parking it beside the survivor. Its corpus was not deleted with it: the
    // seven fixtures under fixtures/highlight/*.duo and their span sidecars are
    // now measured by `highlight-corpus` below, in the surviving vocabulary.
    //
    // highlight-corpus -- CLAUDE.md section 0d, executable. Highlighting is a
    // PROJECTION OF THE GRAPH, not a lexer, and the only way to tell those two
    // apart from outside is a corpus containing the glyphs duon overloads: `:`
    // is copula OR invoke and `|` is union OR pipe, and no lexer separates
    // either pair. The gate asserts the role AND the card at named byte
    // offsets, so "it produced highlighting" is not a passing answer.
    //
    // It also gates section 0g's G-TOTAL: every non-whitespace byte carries a
    // role, and an undecidable span DIAGNOSES rather than defaulting. The
    // negative control in fixtures/highlight/mixed/ is what keeps the
    // "0 unresolved spans" row from being the broken kind of zero.
    //
    // It publishes the three G-TOTAL numbers -- coverage, ambiguity,
    // provenance -- over BOTH corpora at once, which is what gaps/GAP-078.md's
    // falsifier asked for: a coverage percentage published without naming the
    // taxonomy behind it means the gap was closed by forgetting. There is one
    // taxonomy now, so there is one set of numbers. SPECIFICITY is reported
    // separately because Pass 118 makes it the bar coverage is not.
    const highlight_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/highlight.duo" });
    highlight_cmd.setCwd(b.path("."));
    highlight_cmd.step.dependOn(b.getInstallStep());
    const highlight_step = b.step("highlight-corpus", "Pass 113-119: the golden role corpus, totality, the H-1 proofs by value, and specificity; ratchets");
    highlight_step.dependOn(&highlight_cmd.step);

    // U1 -- Pass 105 section 4's `std@{ ambient = false }`, executable. The one
    // charter row that is effective immediately rather than at 0.1, so it is a
    // step rather than a plan. It ratchets off a measured baseline for the same
    // reason audit100 does: std has ambient reach today, and a gate that is red
    // on the day it ships is a gate people learn to skip. The number has to be
    // VISIBLE and fall; it does not have to be zero tomorrow.
    const capability_scan_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/capability_scan.duo" });
    capability_scan_cmd.setCwd(b.path("."));
    capability_scan_cmd.step.dependOn(b.getInstallStep());
    const capability_scan_step = b.step("capability-scan", "Pass 105 U1: ambient fs/net/clock/rand/proc/fault reach in lib/std; ratchets");
    capability_scan_step.dependOn(&capability_scan_cmd.step);

    // APPLY-ONE -- c0 section 43 `law.brace` and section 44 `law.apply.one`.
    // A step of its own because the positive fixture and the negative twin are
    // only evidence when they are read TOGETHER: either alone passes under a
    // compiler that had picked one reading for every brace, which is the state
    // gap[088] measured and gap[092] still carries. The runner also checks the
    // OWED row in the direction it currently fails, so the gate goes red the day
    // descriptor application starts working -- a gate that cannot notice its own
    // gap closing is decoration.
    const apply_one_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/applyone.duo" });
    apply_one_cmd.setCwd(b.path("."));
    apply_one_cmd.step.dependOn(b.getInstallStep());
    const apply_one_step = b.step("apply-one", "c0 section 43/44: one brace form, three outcomes; descriptor row owed by gap[092]");
    apply_one_step.dependOn(&apply_one_cmd.step);

    // RECOGNITION -- Pass 116 section 0a, the AUDIT v4 row, executable. It is a
    // step of its own rather than a row inside audit100 because the whole
    // finding is that `math.` is TWO rules: pure ops that want a value edge and
    // carry no capability, and `math.random`, which is ambient authority and is
    // the ENTIRE `rand` class the capability scan ratchets. One averaged budget
    // would hide that. It also probes its own two blockers live -- the value
    // edge is built AND RUN, never merely `check`ed, because `duo check` exits
    // 0 on `x:abs()` and only codegen rejects it.
    const recognition_scan_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/recognition_scan.duo" });
    recognition_scan_cmd.setCwd(b.path("."));
    recognition_scan_cmd.step.dependOn(b.getInstallStep());
    const recognition_scan_step = b.step("recognition-scan", "Pass 116 s0a: std.mem/std.fmt/std.math and bare math. in lib/std; ratchets");
    recognition_scan_step.dependOn(&recognition_scan_cmd.step);

    // The first sixty seconds of a new user's life, gated. src/build_framework.zig's
    // tests drive parser+sema in-process and stayed green while `duo init` emitted a
    // src/main.duo that `duo check`, `duo build` and `duo run` all rejected. Only a
    // gate that shells the real CLI into a real scratch directory can see that.
    const init_build_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/init_build_smoke.duo" });
    init_build_cmd.setCwd(b.path("."));
    init_build_cmd.step.dependOn(b.getInstallStep());
    const init_build_step = b.step("init-build-smoke", "duo init -> check -> build -> run -> test on a clean directory");
    init_build_step.dependOn(&init_build_cmd.step);

    // U2 -- Pass 105 section 4's `build@deterministic`. The step above is its
    // narrow ancestor and stays: it rebuilds into the SAME cache at the SAME
    // path, which a warm cache satisfies by copying rather than recompiling.
    // This one builds twice into two prefixes with two caches, so neither
    // build can see the other's output, and it diagnoses a divergence rather
    // than only reporting one. It never touches zig-out. Two full builds -- not
    // a tier-0 gate.
    const determinism_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/build_determinism.duo" });
    determinism_cmd.setCwd(b.path("."));
    determinism_cmd.step.dependOn(b.getInstallStep());
    const determinism_step = b.step("build-determinism", "Pass 105 U2: two independent builds, byte-identical artifacts; names the divergence source");
    determinism_step.dependOn(&determinism_cmd.step);

    const repro_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/reproducibility_smoke.duo" });
    repro_cmd.setCwd(b.path("."));
    const repro_step = b.step("reproducibility-smoke", "Pass 11 WP-13: ReleaseFast compiler binary identity across clean rebuilds");
    repro_step.dependOn(&repro_cmd.step);

    const pass11_direct_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/pass11_direct_smoke.duo" });
    pass11_direct_cmd.setCwd(b.path("."));
    pass11_direct_cmd.step.dependOn(b.getInstallStep());
    const pass11_direct_step = b.step("pass11-direct-smoke", "Pass 11: direct ARM64 record proof smoke (macOS AArch64 only)");
    pass11_direct_step.dependOn(&pass11_direct_cmd.step);

    const pass11_module_barrier = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_barrier_checks.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"native_barrier_checks:"},
    });
    const run_pass11_module_barrier = b.addRunArtifact(pass11_module_barrier);

    const pass11_module_target = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/target_model.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_pass11_module_target = b.addRunArtifact(pass11_module_target);

    const pass11_module_proof = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/proof_carrying.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"seed claims"},
    });
    const run_pass11_module_proof = b.addRunArtifact(pass11_module_proof);

    const pass11_module_ward = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass11_ward_barrier_tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"Pass 11 WP-15"},
    });
    const run_pass11_module_ward = b.addRunArtifact(pass11_module_ward);


    const pass11_module_step = b.step("pass11-module-smoke", "Pass 11: native_barrier_checks + target_model + catalog unit tests (cross-platform)");
    pass11_module_step.dependOn(&run_pass11_module_barrier.step);
    pass11_module_step.dependOn(&run_pass11_module_target.step);
    pass11_module_step.dependOn(&run_pass11_module_proof.step);
    pass11_module_step.dependOn(&run_pass11_module_ward.step);

    const pass11_blob_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/pass11_blob_object_smoke.duo" });
    pass11_blob_cmd.setCwd(b.path("."));
    pass11_blob_cmd.step.dependOn(b.getInstallStep());
    const pass11_blob_step = b.step("pass11-blob-object-smoke", "Pass 11 WP-05: byte blob direct Mach-O object (macOS AArch64 only)");
    pass11_blob_step.dependOn(&pass11_blob_cmd.step);

    const pass11_spill_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/pass11_spill_smoke.duo" });
    pass11_spill_cmd.setCwd(b.path("."));
    pass11_spill_cmd.step.dependOn(b.getInstallStep());
    const pass11_spill_step = b.step("pass11-spill-smoke", "Pass 11 WP-03: register spill proof (macOS AArch64 only)");
    pass11_spill_step.dependOn(&pass11_spill_cmd.step);



    const pass11_native_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_backend.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"Pass 11"},
    });
    linkProductionKeywordClassify(b, pass11_native_tests.root_module);
    const run_pass11_native_tests = b.addRunArtifact(pass11_native_tests);
    // Rehomed: this exercises the LIVE native backend ("Pass 11" filter over
    // src/native_backend.zig). Its old consumer, pass11-gate, ran the deleted
    // catalog apparatus — the coverage is real and outlived the gate.
    test_step.dependOn(&run_pass11_native_tests.step);















    const pass34_l1_proof = b.addRunArtifact(exe);
    pass34_l1_proof.addArgs(&.{ "run", "examples/l1_module_sealed_proof.duo" });
    pass34_l1_proof.step.dependOn(b.getInstallStep());
    pass34_l1_proof.setCwd(b.path("."));

    const native_diff_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/native_differential.duo" });
    native_diff_cmd.step.dependOn(b.getInstallStep());
    native_diff_cmd.setCwd(b.path("."));
    const native_diff_step = b.step("native-differential", "Direct ARM64 backend must agree with the C backend on the native corpus");
    native_diff_step.dependOn(&native_diff_cmd.step);

    // Pass 100 §22's generated capability table. It reads the SAME corpus
    // native-differential gates and reports the whole ladder — described,
    // parsed, checked, C path, direct-native, differentially proven, canonical
    // — by running the compiler at each rung rather than by asserting a list.
    // It is a report, not a second gate: it fails only when it could not have
    // measured anything.
    const capability_table_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/capability_table.duo" });
    capability_table_cmd.step.dependOn(b.getInstallStep());
    capability_table_cmd.setCwd(b.path("."));
    const capability_table_step = b.step("capability-table", "Pass 100 §22: derive the described->canonical ladder from the native corpus");
    capability_table_step.dependOn(&capability_table_cmd.step);

    // Pass 100 §19's `blocks-passing/blocks-total` — the metric §22 calls "the
    // project's first honest number". The five golden blocks of §20 are
    // EXTRACTED from docs/spec/pass100.md on every run, so there is no tracked
    // copy to drift, and each construct they need also carries a fixture that
    // prints a value the fixture itself declares. Both counts ratchet.
    const spec_corpus_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/spec_corpus.duo" });
    spec_corpus_cmd.step.dependOn(b.getInstallStep());
    spec_corpus_cmd.setCwd(b.path("."));
    const spec_corpus_step = b.step("spec-corpus", "Pass 100 §19/§20: golden corpus blocks-passing + per-construct fixtures, ratcheted");
    spec_corpus_step.dependOn(&spec_corpus_cmd.step);

    // constitution §21 `law.identity.three` + `law.dedup`, gap[103]. The
    // relation store keyed every edge on a descriptor's TEXT, which is wrong
    // in both directions the moment packages, renames, versions or private
    // descriptors exist. Two rows of checks, because the failure has two very
    // different shapes: the fixtures pin SER and the printed answer BY VALUE,
    // and a scan pins the quarantine — resolving a spelling is the one place a
    // byte comparison is correct, and it lives in `Names`. The scan's zero
    // carries its own positive control, because a blind scanner also reads 0.
    const relation_id_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/relationid.duo" });
    relation_id_cmd.step.dependOn(b.getInstallStep());
    relation_id_cmd.setCwd(b.path("."));
    const relation_id_step = b.step("relation-id", "constitution §21: relation-store semantic identity — SER by value + the byte-comparison quarantine");
    relation_id_step.dependOn(&relation_id_cmd.step);

    // constitution §46 `law.nominal`, second clause: "a nominal descriptor over
    // a primitive costs no boxing". The spec-corpus row above proves the
    // MEANING — 914436 cannot come out of a `feet` that lost its descriptor —
    // and proves nothing at all about the COST, because a boxed double adds
    // just as correctly. This gate reads the emitted C and carries its own
    // positive control: a program that boxes must trip the same predicate, or
    // the gate reports FAIL and no verdict.
    const nominal_zero_cost_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/nominal_zero_cost.duo" });
    nominal_zero_cost_cmd.step.dependOn(b.getInstallStep());
    nominal_zero_cost_cmd.setCwd(b.path("."));
    const nominal_zero_cost_step = b.step("nominal-zero-cost", "constitution §46: a nominal descriptor costs no box, read off the emitted C");
    nominal_zero_cost_step.dependOn(&nominal_zero_cost_cmd.step);

    // Pass 106: twenty MUNDANE programs plus one fixture per numerics/text row.
    // The boring set ratchets a passing count; the table set asserts MEASURED
    // behaviour, so it is a change detector rather than a conformance claim.
    const boring_corpus_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/boring_corpus.duo" });
    boring_corpus_cmd.step.dependOn(b.getInstallStep());
    boring_corpus_cmd.setCwd(b.path("."));
    const boring_corpus_step = b.step("boring-corpus", "Pass 106: everyday programs + the measured numerics/text pages, ratcheted");
    boring_corpus_step.dependOn(&boring_corpus_cmd.step);

    // GAP-081: the conversion edge, by VALUE. Both faces, both lowerings, and
    // the input that used to answer 0 — a conversion that compiles and reports
    // 0 for "abc" is the failure mode this tree already paid for once, so
    // "17 -> 17" is only half of what this asserts.
    const convert_proof_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/convert_proof.duo" });
    convert_proof_cmd.step.dependOn(b.getInstallStep());
    convert_proof_cmd.setCwd(b.path("."));
    const convert_proof_step = b.step("convert-proof", "GAP-081: str -> i64 in both faces and both lowerings, and a refusal on non-numeric input");
    convert_proof_step.dependOn(&convert_proof_cmd.step);

    // The canonicalizer itself, DRY RUN. It reports what it would rewrite and
    // writes nothing; `CONVERTCANON_APPLY=1` is the only thing that writes.
    const convert_canon_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/convert_canon.duo" });
    convert_canon_cmd.step.dependOn(b.getInstallStep());
    convert_canon_cmd.setCwd(b.path("."));
    const convert_canon_step = b.step("convert-canon", "Pass 121 §17: rewrite to(str) sites to the receiver face, witnessed (dry run)");
    convert_canon_step.dependOn(&convert_canon_cmd.step);

    const direct_link_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/direct_module_link_proof.duo" });
    direct_link_cmd.step.dependOn(b.getInstallStep());
    direct_link_cmd.setCwd(b.path("."));
    const direct_link_step = b.step("direct-module-link", "A direct-backend program must be able to call a req'd Duo module");
    direct_link_step.dependOn(&direct_link_cmd.step);




    const idiom_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/duo_idiom_gate.duo" });
    idiom_cmd.setCwd(b.path("."));
    const idiom_step = b.step("idiom-gate", "Every .duo file must use canonical Duo idioms");
    idiom_step.dependOn(&idiom_cmd.step);


    const bench_proof_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/run_benchmark_proof.duo" });
    bench_proof_cmd.setCwd(b.path("."));
    bench_proof_cmd.step.dependOn(b.getInstallStep());
    const bench_proof_step = b.step("bench-proof-gate", "P0 benchmark 3-profile correctness + proof artifacts");
    bench_proof_step.dependOn(&bench_proof_cmd.step);

    const duo_idiom_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/duo_idiom_gate.duo" });
    duo_idiom_cmd.setCwd(b.path("."));
    duo_idiom_cmd.step.dependOn(b.getInstallStep());
    const duo_idiom_step = b.step("duo-idiom-gate", "Enforce compact idiomatic .duo in scripts/ and examples/");
    duo_idiom_step.dependOn(&duo_idiom_cmd.step);



    const pass16_m1_diff = b.addRunArtifact(exe);
    pass16_m1_diff.addArgs(&.{ "run", "examples/pass12_m1_diff.duo" });
    pass16_m1_diff.step.dependOn(b.getInstallStep());
    pass16_m1_diff.setCwd(b.path("."));

    const pass16_m1_proof = b.addRunArtifact(exe);
    pass16_m1_proof.addArgs(&.{ "run", "examples/pass16_m1_lexer_proof.duo" });
    pass16_m1_proof.step.dependOn(b.getInstallStep());
    pass16_m1_proof.setCwd(b.path("."));

    const pass16_source_cursor_proof = b.addRunArtifact(exe);
    pass16_source_cursor_proof.addArgs(&.{ "run", "examples/pass16_source_cursor_proof.duo" });
    pass16_source_cursor_proof.step.dependOn(b.getInstallStep());
    pass16_source_cursor_proof.setCwd(b.path("."));

    const pass16_source_module_proof = b.addRunArtifact(exe);
    pass16_source_module_proof.addArgs(&.{ "run", "examples/pass16_source_module_proof.duo" });
    pass16_source_module_proof.step.dependOn(b.getInstallStep());
    pass16_source_module_proof.setCwd(b.path("."));

    const pass16_lexer_corpus_proof = b.addRunArtifact(exe);
    pass16_lexer_corpus_proof.addArgs(&.{ "run", "examples/pass16_lexer_corpus_proof.duo" });
    pass16_lexer_corpus_proof.step.dependOn(b.getInstallStep());
    pass16_lexer_corpus_proof.setCwd(b.path("."));

    // The token-for-token equality proof against src/lexer.zig — the evidence
    // SH-03's "duo_canonical" claim rests on. It was NOT gated, and silently
    // stopped running when lib/std/str.duo became a native-direct module: the
    // Duo lexer still compiled, but `req "std.str"` failed at runtime, so the
    // proof was unrunnable while the matrix still reported equality.
    const pass16_lexer_fingerprint = b.addRunArtifact(exe);
    // --backend=c deliberately: the NATIVE backend still fails to link this
    // one ("native linker failed" at lexer.duo's @c.export sites). Gating the
    // proof on the backend where it runs is worth more than not gating it at
    // all; the native-path failure is tracked separately.
    pass16_lexer_fingerprint.addArgs(&.{ "run", "--backend=c", "examples/pass16_lexer_fingerprint_differential.duo" });
    pass16_lexer_fingerprint.step.dependOn(b.getInstallStep());
    pass16_lexer_fingerprint.setCwd(b.path("."));

    const pass16_lexer_embed = b.addRunArtifact(exe);
    pass16_lexer_embed.addArgs(&.{ "run", "examples/pass16_lexer_embed_proof.duo" });
    pass16_lexer_embed.step.dependOn(b.getInstallStep());
    pass16_lexer_embed.setCwd(b.path("."));

    const pass16_lexer_tokenize = b.addRunArtifact(exe);
    pass16_lexer_tokenize.addArgs(&.{ "run", "examples/pass16_lexer_tokenize_proof.duo" });
    pass16_lexer_tokenize.step.dependOn(b.getInstallStep());
    pass16_lexer_tokenize.setCwd(b.path("."));

    // MP4-B02 — the state-faithful bulk tokenize entry. `duo_lexer_step`
    // rebuilds a Lexer at a byte offset and so drops peek/hint state, which
    // silently mis-lexes `fun f(): T =`; this runs the whole file on one Lexer
    // and is differenced against the same fingerprint oracle.
    // MP4-B02 — per-token text into a host arena, and the pinned divergence:
    // Duo returns the raw source span for escaped strings, src/lexer.zig decodes.
    const pass16_lexer_tokenize_text = b.addRunArtifact(exe);
    pass16_lexer_tokenize_text.addArgs(&.{ "run", "examples/pass16_lexer_tokenize_text_proof.duo" });
    pass16_lexer_tokenize_text.step.dependOn(b.getInstallStep());
    pass16_lexer_tokenize_text.setCwd(b.path("."));

    // MP4-B02 — token TEXT differential. The kind differential hashes only
    // kinds, so text equivalence was unproven: either lexer could return wrong
    // bytes for every string literal and stay green.
    const pass16_lexer_text_diff = b.addRunArtifact(exe);
    pass16_lexer_text_diff.addArgs(&.{ "run", "--backend=c", "examples/pass16_lexer_text_differential.duo" });
    pass16_lexer_text_diff.step.dependOn(b.getInstallStep());
    pass16_lexer_text_diff.setCwd(b.path("."));

    const pass16_lexer_tokenize_all = b.addRunArtifact(exe);
    pass16_lexer_tokenize_all.addArgs(&.{ "run", "examples/pass16_lexer_tokenize_all_proof.duo" });
    pass16_lexer_tokenize_all.step.dependOn(b.getInstallStep());
    pass16_lexer_tokenize_all.setCwd(b.path("."));

    const pass16_parser_corpus = b.addRunArtifact(exe);
    pass16_parser_corpus.addArgs(&.{ "run", "examples/pass16_parser_corpus_proof.duo" });
    pass16_parser_corpus.step.dependOn(b.getInstallStep());
    pass16_parser_corpus.setCwd(b.path("."));

    const pass16_m1_smoke_step = b.step("pass16-m1-smoke", "Pass 16 M1: keyword + cursor + lexer corpus + embed + tokenize proofs");
    pass16_m1_smoke_step.dependOn(&pass16_m1_diff.step);
    pass16_m1_smoke_step.dependOn(&pass16_m1_proof.step);
    pass16_m1_smoke_step.dependOn(&pass16_source_cursor_proof.step);
    pass16_m1_smoke_step.dependOn(&pass16_source_module_proof.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_corpus_proof.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_fingerprint.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_embed.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_tokenize.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_text_diff.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_tokenize_all.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_tokenize_text.step);
    pass16_m1_smoke_step.dependOn(&pass16_parser_corpus.step);

    const passes_smoke_cmd = b.addRunArtifact(exe);
    passes_smoke_cmd.addArg("catalog");
    passes_smoke_cmd.addArg("audit");
    passes_smoke_cmd.addArg("check");
    passes_smoke_cmd.step.dependOn(b.getInstallStep());
    passes_smoke_cmd.setCwd(b.path("."));
    const passes_smoke_step = b.step("passes-11-14-smoke", "Pass 11–14 native catalog smoke + comprehensive audit (cross-platform)");
    passes_smoke_step.dependOn(&passes_smoke_cmd.step);

    const passes_audit_cmd = b.addRunArtifact(exe);
    passes_audit_cmd.addArg("catalog");
    passes_audit_cmd.addArg("audit");
    passes_audit_cmd.addArg("check");
    passes_audit_cmd.step.dependOn(b.getInstallStep());
    passes_audit_cmd.setCwd(b.path("."));
    const passes_audit_step = b.step("passes-audit-gate", "Cross-pass audit gate (native check, cross-platform)");
    passes_audit_step.dependOn(&passes_audit_cmd.step);


    // Agent-smoke gate (tier-0): public safety + coordination/stdlib/meta smokes
    const agent_smoke_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/duo_lock.duo", "--", "./zig-out/bin/duo", "run", "scripts/agent_smoke.duo" });
    agent_smoke_cmd.setCwd(b.path("."));
    agent_smoke_cmd.step.dependOn(b.getInstallStep());
    const agent_smoke_step = b.step("agent-smoke", "Run tier-0 agent-smoke gate (public safety, coordination, stdlib, meta)");
    agent_smoke_step.dependOn(&public_safety_cmd.step);
    agent_smoke_step.dependOn(&agent_smoke_cmd.step);
    test_step.dependOn(agent_smoke_step);

    // The compile-time string hash (codegen/sema `calc_lua_hash`) and the
    // runtime one (`calc_hash` in the emitted prelude) are written twice and
    // must agree bit for bit; a divergence splits the intern pool and shows up
    // as a wrong answer, not an error. Long strings hash a SAMPLE, so the two
    // spellings are no longer trivially the same loop. This fixture differences
    // them on both sides of the 32-byte boundary and carries its own controls.
    const hash_agreement_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "examples/hash_agreement.duo" });
    hash_agreement_cmd.setCwd(b.path("."));
    hash_agreement_cmd.step.dependOn(b.getInstallStep());
    const hash_agreement_step = b.step("hash-agreement", "Compile-time vs runtime string hash must agree (intern pool)");
    hash_agreement_step.dependOn(&hash_agreement_cmd.step);
    agent_smoke_step.dependOn(&hash_agreement_cmd.step);

    // MCP gate. All three duo MCP servers (duo-bench, duo-lsp, zls) were DEAD —
    // not slow, dead — for an unknown period, and nothing noticed: they
    // compiled, so every check that existed was satisfied, while `duo run`
    // failed at link time on a `req` inside a tool handler. Coordination across
    // parallel agent sessions ran with no coordination tool at all, and the
    // damage was measurable — three gap-number collisions in one night plus
    // repeated sweep-commits.
    //
    // The gate does real JSON-RPC over stdio and asserts response BYTES: exact
    // tool counts (not floors), named coordination tools, a value round trip
    // through the file-claim lock that requires the lock to REFUSE a second
    // owner, and by-name calls to seven handlers that used to answer nothing at
    // all. It spawns the servers in a scratch cwd, because `duo run x.duo`
    // drops `x.out` beside itself and this gate guards the tree it runs in.
    const mcp_gate_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "tools/mcp/mcp_gate.duo" });
    mcp_gate_cmd.setCwd(b.path("."));
    mcp_gate_cmd.step.dependOn(b.getInstallStep());
    const mcp_gate_step = b.step("mcp-gate", "MCP servers must handshake, serve their full tool census, and answer by value");
    mcp_gate_step.dependOn(&mcp_gate_cmd.step);
    // Tier 0: a dead MCP server is a dead coordination plane.
    agent_smoke_step.dependOn(&mcp_gate_cmd.step);

    // lsp-gate — the LSP is the same kind of program, and it had NO gate at all.
    //
    // It was carrying the same class of defect the MCP servers were: on
    // 2026-08-08 `textDocument/didClose` SEGFAULTED the server. Exit 139, no
    // diagnostic, no partial answer, no reply to anything afterwards. `t[k] =
    // nil` does not remove a key in Duo, so `flush_dirty` — which runs after
    // EVERY message — walked the docs table, found the nil and dereferenced it.
    // Every editor closes documents; nobody had ever run one against it.
    //
    // The gate speaks real LSP framing (`Content-Length: N\r\n\r\n{…}`) and
    // asserts response BYTES: the twelve advertised capabilities, the generated
    // 17+13 role legend verbatim, a value round trip through hover, definition
    // and documentSymbol, the exact delta-encoded semantic-token stream for the
    // golden copula fixture, the CDR inlay hint, and the code lens witness
    // counts. Everything scored happens AFTER a close, so a server that dies
    // mid-session cannot score. Positive-controlled by driving it at corrupted
    // copies via LSPGATE_SERVER — see the file header for the three runs.
    const lsp_gate_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "tools/lsp/gate.duo" });
    lsp_gate_cmd.setCwd(b.path("."));
    lsp_gate_cmd.step.dependOn(b.getInstallStep());
    const lsp_gate_step = b.step("lsp-gate", "The LSP must handshake, survive a document close, and answer by value");
    lsp_gate_step.dependOn(&lsp_gate_cmd.step);
    // Tier 0: an untested language server is an untested front end, and Pass 117
    // §0g gates every front end.
    agent_smoke_step.dependOn(&lsp_gate_cmd.step);

    // G-061 tier-0 metaprogramming smokes (combinator dispatch + derive bundles)
    const meta_smoke_paths = [_][]const u8{
        "examples/metaprogramming_test.duo",
        "examples/derive_bundle_smoke.duo",
        "examples/meta_derive_power_cascade.duo",
        "examples/comptime_map_satisfies_smoke.duo",
        "examples/meta_expand_showcase.duo",
        "examples/meta_match_showcase.duo",
        "examples/meta_power_permute_showcase.duo",
        "examples/std_metaprogramming_modules_smoke.duo",
    };
    const meta_smoke_step = b.step("meta-smoke", "Run G-061 tier-0 @comp.* metaprogramming smokes");
    meta_smoke_step.dependOn(b.getInstallStep());
    inline for (meta_smoke_paths) |path| {
        const cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/duo_lock.duo", "--", "./zig-out/bin/duo", "run", path });
        cmd.setCwd(b.path("."));
        meta_smoke_step.dependOn(&cmd.step);
    }

    // G-061 strict dispatch gate: metaprogramming smoke under DUO_TRANSFORM_GATE=1
    const meta_gate_cmd = b.addSystemCommand(&.{
        "bash",                                                                                                                                        "-c",
        "DUO_TRANSFORM_GATE=1 DUO_PROVENANCE=1 ./zig-out/bin/duo run scripts/duo_lock.duo -- ./zig-out/bin/duo run examples/metaprogramming_test.duo",
    });
    meta_gate_cmd.setCwd(b.path("."));
    meta_gate_cmd.step.dependOn(b.getInstallStep());
    const meta_gate_step = b.step("meta-gate", "Run tier-0 metaprogramming smoke with DUO_TRANSFORM_GATE=1");
    meta_gate_step.dependOn(&meta_gate_cmd.step);
}
