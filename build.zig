const std = @import("std");

fn linkProductionKeywordClassify(b: *std.Build, mod: *std.Build.Module) void {
    mod.addCSourceFile(.{
        .file = b.path("src/duo_keyword_classify.c"),
        .flags = &.{"-std=c11"},
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

    const test_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_compile_fail_tests.sh" });
    test_cmd.setCwd(b.path("."));
    test_cmd.step.dependOn(b.getInstallStep());
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

    const no_ansi_reports_cmd = b.addSystemCommand(&.{ "bash", "scripts/assert_no_ansi_reports.sh" });
    no_ansi_reports_cmd.setCwd(b.path("."));
    no_ansi_reports_cmd.step.dependOn(b.getInstallStep());
    const no_ansi_reports_step = b.step("no-ansi-reports", "Assert report ANSI/no-color styling contract");
    no_ansi_reports_step.dependOn(&no_ansi_reports_cmd.step);
    const report_styling_step = b.step("report-styling", "Assert rich and no-color test report styling");
    report_styling_step.dependOn(&no_ansi_reports_cmd.step);
    test_step.dependOn(&no_ansi_reports_cmd.step);

    const gpu_bench_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_gpu_benchmark.sh" });
    gpu_bench_cmd.setCwd(b.path("."));
    gpu_bench_cmd.step.dependOn(b.getInstallStep());
    const gpu_bench_step = b.step("gpu-bench", "Run Duo vs GPU Metal benchmark");
    gpu_bench_step.dependOn(&gpu_bench_cmd.step);
    test_step.dependOn(&gpu_bench_cmd.step);

    const bench_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_benchmark.sh" });
    bench_cmd.setCwd(b.path("."));
    bench_cmd.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run Duo vs C benchmark suite");
    bench_step.dependOn(&bench_cmd.step);

    const cross_bench_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_cross_benchmark.sh" });
    cross_bench_cmd.setCwd(b.path("."));
    cross_bench_cmd.step.dependOn(b.getInstallStep());
    const cross_bench_step = b.step("cross-bench", "Run cross-language benchmark (Duo vs C vs Lua vs LuaJIT)");
    cross_bench_step.dependOn(&cross_bench_cmd.step);

    const wasm_bench_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_wasm_benchmark.sh" });
    wasm_bench_cmd.setCwd(b.path("."));
    wasm_bench_cmd.step.dependOn(b.getInstallStep());
    const wasm_bench_step = b.step("wasm-bench", "Run WASM runtime benchmark (wasmtime, wazero, wasm3, iwasm, wasmer, spin)");
    wasm_bench_step.dependOn(&wasm_bench_cmd.step);

    const ml_bench_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_ml_benchmark.sh" });
    ml_bench_cmd.setCwd(b.path("."));
    ml_bench_cmd.step.dependOn(b.getInstallStep());
    const ml_bench_step = b.step("ml-bench", "Run ML benchmark suite (Duo vs C)");
    ml_bench_step.dependOn(&ml_bench_cmd.step);

    const honest_bench_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_honest_benchmark.sh" });
    honest_bench_cmd.setCwd(b.path("."));
    honest_bench_cmd.step.dependOn(b.getInstallStep());
    const honest_bench_step = b.step("honest-bench", "Run honest benchmark (no precomputation, runtime inputs)");
    honest_bench_step.dependOn(&honest_bench_cmd.step);

    const compile_size_bench_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_compile_size_benchmark.sh" });
    compile_size_bench_cmd.setCwd(b.path("."));
    compile_size_bench_cmd.step.dependOn(b.getInstallStep());
    const compile_size_bench_step = b.step("compile-size-bench", "Track compile time and binary size vs C");
    compile_size_bench_step.dependOn(&compile_size_bench_cmd.step);

    // Public safety pre-scan (Pass 10 A19)
    const public_safety_cmd = b.addSystemCommand(&.{ "bash", "./scripts/public_safety_scan.sh" });
    public_safety_cmd.setCwd(b.path("."));
    const public_safety_step = b.step("public-safety", "Scan tracked files for secrets and personal paths (Pass 10 A19)");
    public_safety_step.dependOn(&public_safety_cmd.step);

    const repo_hygiene_cmd = b.addSystemCommand(&.{ "bash", "./scripts/repo_hygiene.sh" });
    repo_hygiene_cmd.setCwd(b.path("."));
    const repo_hygiene_step = b.step("repo-hygiene", "Pass 11 WP-12: forbidden root artifacts and tracked agent noise");
    repo_hygiene_step.dependOn(&repo_hygiene_cmd.step);

    const repro_cmd = b.addSystemCommand(&.{ "bash", "./scripts/reproducibility_smoke.sh" });
    repro_cmd.setCwd(b.path("."));
    const repro_step = b.step("reproducibility-smoke", "Pass 11 WP-13: ReleaseFast compiler binary identity across clean rebuilds");
    repro_step.dependOn(&repro_cmd.step);

    const pass11_direct_cmd = b.addSystemCommand(&.{ "bash", "./scripts/pass11_direct_smoke.sh" });
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

    const pass11_blob_cmd = b.addSystemCommand(&.{ "bash", "./scripts/pass11_blob_object_smoke.sh" });
    pass11_blob_cmd.setCwd(b.path("."));
    pass11_blob_cmd.step.dependOn(b.getInstallStep());
    const pass11_blob_step = b.step("pass11-blob-object-smoke", "Pass 11 WP-05: byte blob direct Mach-O object (macOS AArch64 only)");
    pass11_blob_step.dependOn(&pass11_blob_cmd.step);

    const pass11_spill_cmd = b.addSystemCommand(&.{ "bash", "./scripts/pass11_spill_smoke.sh" });
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
    const run_pass11_gate_tests = b.addRunArtifact(pass11_gate_tests);

    const pass11_native_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_backend.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"Pass 11"},
    });
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

    const pass16_m1_verify = b.addRunArtifact(exe);
    pass16_m1_verify.addArgs(&.{ "selfhost", "verify" });
    pass16_m1_verify.step.dependOn(b.getInstallStep());
    pass16_m1_verify.setCwd(b.path("."));

    const pass16_lexer_corpus_proof = b.addRunArtifact(exe);
    pass16_lexer_corpus_proof.addArgs(&.{ "run", "examples/pass16_lexer_corpus_proof.duo" });
    pass16_lexer_corpus_proof.step.dependOn(b.getInstallStep());
    pass16_lexer_corpus_proof.setCwd(b.path("."));

    const pass16_lexer_embed = b.addRunArtifact(exe);
    pass16_lexer_embed.addArgs(&.{ "run", "examples/pass16_lexer_embed_proof.duo" });
    pass16_lexer_embed.step.dependOn(b.getInstallStep());
    pass16_lexer_embed.setCwd(b.path("."));

    const pass16_lexer_tokenize = b.addRunArtifact(exe);
    pass16_lexer_tokenize.addArgs(&.{ "run", "examples/pass16_lexer_tokenize_proof.duo" });
    pass16_lexer_tokenize.step.dependOn(b.getInstallStep());
    pass16_lexer_tokenize.setCwd(b.path("."));

    const pass16_m1_smoke_step = b.step("pass16-m1-smoke", "Pass 16 M1: keyword + cursor + lexer corpus + embed + tokenize proofs");
    pass16_m1_smoke_step.dependOn(&pass16_m1_diff.step);
    pass16_m1_smoke_step.dependOn(&pass16_m1_proof.step);
    pass16_m1_smoke_step.dependOn(&pass16_source_cursor_proof.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_corpus_proof.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_embed.step);
    pass16_m1_smoke_step.dependOn(&pass16_lexer_tokenize.step);
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
    pass_gates_step.dependOn(passes_audit_step);

    // Agent-smoke gate (tier-0): public safety + coordination/stdlib/meta smokes
    const agent_smoke_cmd = b.addSystemCommand(&.{ "bash", "scripts/duo_lock.sh", "--", "./zig-out/bin/duo", "run", "scripts/agent_smoke.duo" });
    agent_smoke_cmd.setCwd(b.path("."));
    agent_smoke_cmd.step.dependOn(b.getInstallStep());
    const agent_smoke_step = b.step("agent-smoke", "Run tier-0 agent-smoke gate (public safety, coordination, stdlib, meta)");
    agent_smoke_step.dependOn(&public_safety_cmd.step);
    agent_smoke_step.dependOn(&agent_smoke_cmd.step);
    test_step.dependOn(agent_smoke_step);
}
