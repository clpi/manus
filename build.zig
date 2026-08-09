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

    // ── ward conformance suite (ext/ward) ───────────────────────────────────
    // ward is a WASM runtime shipping in the release, and until 2026-08-08 it
    // had NO test suite: `ext/ward/test/main.duo` required four modules that
    // had been deleted and did not parse, so the only checking was a benchmark
    // harness's `-1` filter. This step builds the runtime and differences every
    // fixture against wasmtime BY VALUE, under both engines and both entry
    // shapes, and refuses to print a score until its own controls pass (exit 3).
    //
    // Both commands run with cwd = ext/ward so `duo run`'s `.out` artifact
    // lands where ext/ward/.gitignore already covers it, and the compiled
    // runtime goes to /tmp for the reason that directory's .gitignore states:
    // a stale binary sitting next to the source is this project's oldest
    // measurement bug.
    // Paths are relative to the CHILD's cwd (ext/ward), which is what setCwd
    // establishes before exec. An absolute path via the build root would be
    // nicer to read, and the API for it has moved twice in zig master.
    const ward_bin_path = "../../zig-out/bin/ward-conform";
    const duo_bin_path = "../../zig-out/bin/duo";
    const ward_build_cmd = b.addSystemCommand(&.{
        duo_bin_path,  "compile",     "src/ward.duo",
        "--backend=c", "--emit",      "exe",
        "-o",          ward_bin_path,
    });
    ward_build_cmd.setCwd(b.path("ext/ward"));
    ward_build_cmd.step.dependOn(b.getInstallStep());
    const ward_test_cmd = b.addSystemCommand(&.{ duo_bin_path, "run", "test/conform.duo" });
    ward_test_cmd.setEnvironmentVariable("WARD_BIN", ward_bin_path);
    ward_test_cmd.setCwd(b.path("ext/ward"));
    ward_test_cmd.step.dependOn(&ward_build_cmd.step);
    const ward_test_step = b.step("ward-test", "ward conformance: every fixture, both engines, differenced against wasmtime");
    ward_test_step.dependOn(&ward_test_cmd.step);

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

    // The first sixty seconds of a new user's life, gated. src/build_framework.zig's
    // tests drive parser+sema in-process and stayed green while `duo init` emitted a
    // src/main.duo that `duo check`, `duo build` and `duo run` all rejected. Only a
    // gate that shells the real CLI into a real scratch directory can see that.
    const init_build_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/init_build_smoke.duo" });
    init_build_cmd.setCwd(b.path("."));
    init_build_cmd.step.dependOn(b.getInstallStep());
    const init_build_step = b.step("init-build-smoke", "duo init -> check -> build -> run -> test on a clean directory");
    init_build_step.dependOn(&init_build_cmd.step);

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

    const pass11_module_catalog = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass11_catalog.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass11_catalog:"},
    });
    const run_pass11_module_catalog = b.addRunArtifact(pass11_module_catalog);

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

    const pass11_module_catalog_cmd = b.addRunArtifact(exe);
    pass11_module_catalog_cmd.addArg("catalog");
    pass11_module_catalog_cmd.step.dependOn(b.getInstallStep());
    pass11_module_catalog_cmd.setCwd(b.path("."));

    const pass11_module_step = b.step("pass11-module-smoke", "Pass 11: native_barrier_checks + target_model + catalog unit tests (cross-platform)");
    pass11_module_step.dependOn(&run_pass11_module_barrier.step);
    pass11_module_step.dependOn(&run_pass11_module_target.step);
    pass11_module_step.dependOn(&run_pass11_module_catalog.step);
    pass11_module_step.dependOn(&run_pass11_module_proof.step);
    pass11_module_step.dependOn(&run_pass11_module_ward.step);
    pass11_module_step.dependOn(&pass11_module_catalog_cmd.step);

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

    const pass11_gate_audit = b.addRunArtifact(exe);
    pass11_gate_audit.addArgs(&.{ "catalog", "audit", "gate", "pass11" });
    pass11_gate_audit.step.dependOn(b.getInstallStep());
    pass11_gate_audit.setCwd(b.path("."));

    const pass11_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates:"},
    });
    linkProductionKeywordClassify(b, pass11_gate_tests.root_module);
    const run_pass11_gate_tests = b.addRunArtifact(pass11_gate_tests);

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

    const pass11_gate_step = b.step("pass11-gate", "Pass 11 Profile A closure gate (native catalog + module tests, cross-platform)");
    pass11_gate_step.dependOn(&pass11_gate_audit.step);
    pass11_gate_step.dependOn(&run_pass11_gate_tests.step);
    pass11_gate_step.dependOn(&run_pass11_native_tests.step);

    const pass12_gate_cmd = b.addRunArtifact(exe);
    pass12_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass12" });
    pass12_gate_cmd.step.dependOn(b.getInstallStep());
    pass12_gate_cmd.setCwd(b.path("."));
    const pass12_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass12"},
    });
    linkProductionKeywordClassify(b, pass12_gate_tests.root_module);
    const run_pass12_gate_tests = b.addRunArtifact(pass12_gate_tests);
    const pass12_gate_step = b.step("pass12-gate", "Pass 12 semantic autonomy gate (native, cross-platform)");
    pass12_gate_step.dependOn(&pass12_gate_cmd.step);
    pass12_gate_step.dependOn(&run_pass12_gate_tests.step);

    const pass13_gate_cmd = b.addRunArtifact(exe);
    pass13_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass13" });
    pass13_gate_cmd.step.dependOn(b.getInstallStep());
    pass13_gate_cmd.setCwd(b.path("."));
    const pass13_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass13"},
    });
    linkProductionKeywordClassify(b, pass13_gate_tests.root_module);
    const run_pass13_gate_tests = b.addRunArtifact(pass13_gate_tests);
    const pass13_gate_step = b.step("pass13-gate", "Pass 13 development control plane gate (native, cross-platform)");
    pass13_gate_step.dependOn(&pass13_gate_cmd.step);
    pass13_gate_step.dependOn(&run_pass13_gate_tests.step);

    const pass14_gate_cmd = b.addRunArtifact(exe);
    pass14_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass14" });
    pass14_gate_cmd.step.dependOn(b.getInstallStep());
    pass14_gate_cmd.setCwd(b.path("."));
    const pass14_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass14"},
    });
    linkProductionKeywordClassify(b, pass14_gate_tests.root_module);
    const run_pass14_gate_tests = b.addRunArtifact(pass14_gate_tests);
    const pass14_gate_step = b.step("pass14-gate", "Pass 14 constructive evolution gate (native, cross-platform)");
    pass14_gate_step.dependOn(&pass14_gate_cmd.step);
    pass14_gate_step.dependOn(&run_pass14_gate_tests.step);

    const pass15_gate_cmd = b.addRunArtifact(exe);
    pass15_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass15" });
    pass15_gate_cmd.step.dependOn(b.getInstallStep());
    pass15_gate_cmd.setCwd(b.path("."));
    const pass15_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass15"},
    });
    linkProductionKeywordClassify(b, pass15_gate_tests.root_module);
    const run_pass15_gate_tests = b.addRunArtifact(pass15_gate_tests);
    const pass15_gate_step = b.step("pass15-gate", "Pass 15 semantic shell gate (native, cross-platform)");
    pass15_gate_step.dependOn(&pass15_gate_cmd.step);
    pass15_gate_step.dependOn(&run_pass15_gate_tests.step);

    const pass16_gate_cmd = b.addRunArtifact(exe);
    pass16_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass16" });
    pass16_gate_cmd.step.dependOn(b.getInstallStep());
    pass16_gate_cmd.setCwd(b.path("."));
    const pass16_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass16"},
    });
    linkProductionKeywordClassify(b, pass16_gate_tests.root_module);
    const run_pass16_gate_tests = b.addRunArtifact(pass16_gate_tests);
    const pass16_gate_step = b.step("pass16-gate", "Pass 16 self-hosted compiler gate (native, cross-platform)");
    pass16_gate_step.dependOn(&pass16_gate_cmd.step);
    pass16_gate_step.dependOn(&run_pass16_gate_tests.step);

    const pass22_gate_cmd = b.addRunArtifact(exe);
    pass22_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass22" });
    pass22_gate_cmd.step.dependOn(b.getInstallStep());
    pass22_gate_cmd.setCwd(b.path("."));
    const pass22_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass22"},
    });
    linkProductionKeywordClassify(b, pass22_gate_tests.root_module);
    const run_pass22_gate_tests = b.addRunArtifact(pass22_gate_tests);
    const pass22_gate_step = b.step("pass22-gate", "Pass 22 graph-native IR gate (native, cross-platform)");
    pass22_gate_step.dependOn(&pass22_gate_cmd.step);
    pass22_gate_step.dependOn(&run_pass22_gate_tests.step);

    const pass19_gate_cmd = b.addRunArtifact(exe);
    pass19_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass19" });
    pass19_gate_cmd.step.dependOn(b.getInstallStep());
    pass19_gate_cmd.setCwd(b.path("."));
    const pass19_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass19"},
    });
    linkProductionKeywordClassify(b, pass19_gate_tests.root_module);
    const run_pass19_gate_tests = b.addRunArtifact(pass19_gate_tests);
    const pass19_gate_step = b.step("pass19-gate", "Pass 19 unified semantic experience gate (native, cross-platform)");
    pass19_gate_step.dependOn(&pass19_gate_cmd.step);
    pass19_gate_step.dependOn(&run_pass19_gate_tests.step);

    const pass23_gate_cmd = b.addRunArtifact(exe);
    pass23_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass23" });
    pass23_gate_cmd.step.dependOn(b.getInstallStep());
    pass23_gate_cmd.setCwd(b.path("."));
    const pass23_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass23"},
    });
    linkProductionKeywordClassify(b, pass23_gate_tests.root_module);
    const run_pass23_gate_tests = b.addRunArtifact(pass23_gate_tests);
    const pass23_gate_step = b.step("pass23-gate", "Pass 23 unified metaprotocols gate (native, cross-platform)");
    pass23_gate_step.dependOn(&pass23_gate_cmd.step);
    pass23_gate_step.dependOn(&run_pass23_gate_tests.step);

    const lua_superset_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass24"},
    });
    linkProductionKeywordClassify(b, lua_superset_gate_tests.root_module);
    const run_lua_superset_gate_tests = b.addRunArtifact(lua_superset_gate_tests);
    const pass24_gate_cmd = b.addRunArtifact(exe);
    pass24_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass24" });
    pass24_gate_cmd.step.dependOn(b.getInstallStep());
    pass24_gate_cmd.setCwd(b.path("."));
    const pass24_gate_step = b.step("pass24-gate", "Pass 24 unified calls + Lua superset + concurrency constitution gate");
    pass24_gate_step.dependOn(&pass24_gate_cmd.step);
    pass24_gate_step.dependOn(&run_lua_superset_gate_tests.step);
    const lua_superset_gate_step = b.step("lua-superset-gate", "Alias for pass24-gate (Lua superset P0)");
    lua_superset_gate_step.dependOn(pass24_gate_step);

    const pass25_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass25"},
    });
    linkProductionKeywordClassify(b, pass25_gate_tests.root_module);
    const run_pass25_gate_tests = b.addRunArtifact(pass25_gate_tests);
    const pass25_gate_cmd = b.addRunArtifact(exe);
    pass25_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass25" });
    pass25_gate_cmd.step.dependOn(b.getInstallStep());
    pass25_gate_cmd.setCwd(b.path("."));
    const pass25_gate_step = b.step("pass25-gate", "Pass 25 semantic unification + lifetimes + bidirectional meta constitution gate");
    pass25_gate_step.dependOn(&pass25_gate_cmd.step);
    pass25_gate_step.dependOn(&run_pass25_gate_tests.step);
    const semantic_unification_gate_step = b.step("semantic-unification-gate", "Alias for pass25-gate");
    semantic_unification_gate_step.dependOn(pass25_gate_step);

    const pass26_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass26"},
    });
    linkProductionKeywordClassify(b, pass26_gate_tests.root_module);
    const run_pass26_gate_tests = b.addRunArtifact(pass26_gate_tests);
    const pass26_gate_cmd = b.addRunArtifact(exe);
    pass26_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass26" });
    pass26_gate_cmd.step.dependOn(b.getInstallStep());
    pass26_gate_cmd.setCwd(b.path("."));
    const pass26_gate_step = b.step("pass26-gate", "Pass 26 foundational closure — five seams + contradiction registry");
    pass26_gate_step.dependOn(&pass26_gate_cmd.step);
    pass26_gate_step.dependOn(&run_pass26_gate_tests.step);
    const foundational_closure_gate_step = b.step("foundational-closure-gate", "Alias for pass26-gate");
    foundational_closure_gate_step.dependOn(pass26_gate_step);

    const pass27_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass27"},
    });
    linkProductionKeywordClassify(b, pass27_gate_tests.root_module);
    const run_pass27_gate_tests = b.addRunArtifact(pass27_gate_tests);
    const pass27_gate_cmd = b.addRunArtifact(exe);
    pass27_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass27" });
    pass27_gate_cmd.step.dependOn(b.getInstallStep());
    pass27_gate_cmd.setCwd(b.path("."));
    const pass27_gate_step = b.step("pass27-gate", "Pass 27 proof bundle + performance/metaprogramming evidence gate");
    pass27_gate_step.dependOn(&pass27_gate_cmd.step);
    pass27_gate_step.dependOn(&run_pass27_gate_tests.step);
    const proof_bundle_gate_step = b.step("proof-bundle-gate", "Alias for pass27-gate");
    proof_bundle_gate_step.dependOn(pass27_gate_step);

    const foundation_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: self-hosting foundation"},
    });
    linkProductionKeywordClassify(b, foundation_gate_tests.root_module);
    const run_foundation_gate_tests = b.addRunArtifact(foundation_gate_tests);
    const foundation_gate_cmd = b.addRunArtifact(exe);
    foundation_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "foundation" });
    foundation_gate_cmd.step.dependOn(b.getInstallStep());
    foundation_gate_cmd.setCwd(b.path("."));
    const foundation_gate_step = b.step("foundation-gate", "Self-hosting foundation catalog + F-G01..F-G10 schema gate (M0)");
    foundation_gate_step.dependOn(&foundation_gate_cmd.step);
    foundation_gate_step.dependOn(&run_foundation_gate_tests.step);
    const self_hosting_foundation_gate_step = b.step("self-hosting-foundation-gate", "Alias for foundation-gate");
    self_hosting_foundation_gate_step.dependOn(foundation_gate_step);

    const pass34_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass34 HPLS"},
    });
    linkProductionKeywordClassify(b, pass34_gate_tests.root_module);
    const run_pass34_gate_tests = b.addRunArtifact(pass34_gate_tests);
    const pass34_gate_cmd = b.addRunArtifact(exe);
    pass34_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass34" });
    pass34_gate_cmd.step.dependOn(b.getInstallStep());
    pass34_gate_cmd.setCwd(b.path("."));
    const pass34_l1_proof = b.addRunArtifact(exe);
    pass34_l1_proof.addArgs(&.{ "run", "examples/l1_module_sealed_proof.duo" });
    pass34_l1_proof.step.dependOn(b.getInstallStep());
    pass34_l1_proof.setCwd(b.path("."));
    const pass34_gate_step = b.step("pass34-gate", "Pass 34 HPLS Frontier catalog Phase 0+1 gate (L6 manifest + L1 seal)");
    pass34_gate_step.dependOn(&pass34_gate_cmd.step);
    pass34_gate_step.dependOn(&run_pass34_gate_tests.step);
    pass34_gate_step.dependOn(&pass34_l1_proof.step);
    const hpls_gate_step = b.step("hpls-gate", "Alias for pass34-gate");
    hpls_gate_step.dependOn(pass34_gate_step);
    const hpls_frontier_gate_step = b.step("hpls-frontier-gate", "Alias for pass34-gate");
    hpls_frontier_gate_step.dependOn(pass34_gate_step);

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

    // Pass 106: twenty MUNDANE programs plus one fixture per numerics/text row.
    // The boring set ratchets a passing count; the table set asserts MEASURED
    // behaviour, so it is a change detector rather than a conformance claim.
    const boring_corpus_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/boring_corpus.duo" });
    boring_corpus_cmd.step.dependOn(b.getInstallStep());
    boring_corpus_cmd.setCwd(b.path("."));
    const boring_corpus_step = b.step("boring-corpus", "Pass 106: everyday programs + the measured numerics/text pages, ratcheted");
    boring_corpus_step.dependOn(&boring_corpus_cmd.step);

    const direct_link_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/direct_module_link_proof.duo" });
    direct_link_cmd.step.dependOn(b.getInstallStep());
    direct_link_cmd.setCwd(b.path("."));
    const direct_link_step = b.step("direct-module-link", "A direct-backend program must be able to call a req'd Duo module");
    direct_link_step.dependOn(&direct_link_cmd.step);

    const pass49_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass49_gate.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_pass49_gate = b.addRunArtifact(pass49_gate_tests);
    const pass49_gate_step = b.step("pass49-gate", "Pass 49 sums/protocols/demand-return proofs");
    pass49_gate_step.dependOn(&run_pass49_gate.step);

    const pass52_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass52_gate.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_pass52_gate = b.addRunArtifact(pass52_gate_tests);
    const pass52_gate_step = b.step("pass52-gate", "Pass 52 no-magic / de-magicking proofs");
    pass52_gate_step.dependOn(&run_pass52_gate.step);

    const pass48_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass48_gate.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_pass48_gate = b.addRunArtifact(pass48_gate_tests);
    const pass48_gate_step = b.step("pass48-gate", "Pass 48 canonical specification consolidation proofs");
    pass48_gate_step.dependOn(&run_pass48_gate.step);

    const idiom_cmd = b.addSystemCommand(&.{ "./zig-out/bin/duo", "run", "scripts/duo_idiom_gate.duo" });
    idiom_cmd.setCwd(b.path("."));
    const idiom_step = b.step("idiom-gate", "Every .duo file must use canonical Duo idioms");
    idiom_step.dependOn(&idiom_cmd.step);

    const pass36_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass36 universal semantic access"},
    });
    linkProductionKeywordClassify(b, pass36_gate_tests.root_module);
    const run_pass36_gate_tests = b.addRunArtifact(pass36_gate_tests);
    const pass36_gate_cmd = b.addRunArtifact(exe);
    pass36_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass36" });
    pass36_gate_cmd.step.dependOn(b.getInstallStep());
    pass36_gate_cmd.setCwd(b.path("."));
    const pass36_gate_step = b.step("pass36-gate", "Pass 36 universal semantic access catalog Phase 0 gate (recorded calculus)");
    pass36_gate_step.dependOn(&pass36_gate_cmd.step);
    pass36_gate_step.dependOn(&run_pass36_gate_tests.step);
    const semantic_access_gate_step = b.step("semantic-access-gate", "Alias for pass36-gate");
    semantic_access_gate_step.dependOn(pass36_gate_step);
    const projection_gate_step = b.step("projection-gate", "Alias for pass36-gate");
    projection_gate_step.dependOn(pass36_gate_step);

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

    const pass21_gate_cmd = b.addRunArtifact(exe);
    pass21_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass21" });
    pass21_gate_cmd.step.dependOn(b.getInstallStep());
    pass21_gate_cmd.setCwd(b.path("."));
    const pass21_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass21"},
    });
    linkProductionKeywordClassify(b, pass21_gate_tests.root_module);
    const run_pass21_gate_tests = b.addRunArtifact(pass21_gate_tests);
    const pass21_gate_step = b.step("pass21-gate", "Pass 21 canonical grammar closure gate (native, cross-platform)");
    pass21_gate_step.dependOn(&pass21_gate_cmd.step);
    pass21_gate_step.dependOn(&run_pass21_gate_tests.step);

    const pass20_gate_cmd = b.addRunArtifact(exe);
    pass20_gate_cmd.addArgs(&.{ "catalog", "audit", "gate", "pass20" });
    pass20_gate_cmd.step.dependOn(b.getInstallStep());
    pass20_gate_cmd.setCwd(b.path("."));
    const pass20_gate_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pass_gates.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"pass_gates: pass20"},
    });
    linkProductionKeywordClassify(b, pass20_gate_tests.root_module);
    const run_pass20_gate_tests = b.addRunArtifact(pass20_gate_tests);
    const pass20_gate_step = b.step("pass20-gate", "Pass 20 universal metaprogramming harness gate (native, cross-platform)");
    pass20_gate_step.dependOn(&pass20_gate_cmd.step);
    pass20_gate_step.dependOn(&run_pass20_gate_tests.step);

    const pass16_cross_platform_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/selfhost_target_matrix.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_pass16_cross_platform_tests = b.addRunArtifact(pass16_cross_platform_tests);
    const pass16_cross_platform_step = b.step("pass16-cross-platform", "Pass 16 §17 target matrix + host-aware gate (native, cross-platform)");
    pass16_cross_platform_step.dependOn(&run_pass16_cross_platform_tests.step);
    pass16_cross_platform_step.dependOn(pass16_gate_step);

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

    const pass16_m1_verify = b.addRunArtifact(exe);
    pass16_m1_verify.addArgs(&.{ "selfhost", "verify" });
    pass16_m1_verify.step.dependOn(b.getInstallStep());
    pass16_m1_verify.setCwd(b.path("."));

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
    pass16_m1_smoke_step.dependOn(&pass16_m1_verify.step);
    pass16_m1_smoke_step.dependOn(pass16_gate_step);

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

    const pass_gates_step = b.step("pass-gates", "All native Pass 11–16 gates (cross-platform, no bash/jq)");
    pass_gates_step.dependOn(pass11_gate_step);
    pass_gates_step.dependOn(pass12_gate_step);
    pass_gates_step.dependOn(pass13_gate_step);
    pass_gates_step.dependOn(pass14_gate_step);
    pass_gates_step.dependOn(pass15_gate_step);
    pass_gates_step.dependOn(pass16_gate_step);
    pass_gates_step.dependOn(pass20_gate_step);
    pass_gates_step.dependOn(pass21_gate_step);
    pass_gates_step.dependOn(pass22_gate_step);
    pass_gates_step.dependOn(pass23_gate_step);
    pass_gates_step.dependOn(pass24_gate_step);
    pass_gates_step.dependOn(lua_superset_gate_step);
    pass_gates_step.dependOn(pass25_gate_step);
    pass_gates_step.dependOn(pass26_gate_step);
    pass_gates_step.dependOn(pass19_gate_step);
    pass_gates_step.dependOn(passes_audit_step);

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
