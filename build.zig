const std = @import("std");
const builtin = @import("builtin");

/// SH-02 + SH-03 production seam. These travel together: any module that
/// reaches `lexer_bridge` reaches both the keyword table and the Duo lexer
/// behind it, so linking them separately only produces undefined symbols later.
///
/// The Duo lexer artifact also defines a STRONG `duo_keyword_classify`, which
/// overrides the weak one in src/keyword_classify.c — that file was written
/// weak for exactly this case.
fn linkProductionKeywordClassify(b: *std.Build, mod: *std.Build.Module) void {
    // Weak `duo_keyword_classify` from the classify C projection. The lexer
    // artifact currently emits a strong definition of the same symbol; weak
    // loses. Delete this unit when classify.id is the sole linked producer.
    mod.addCSourceFile(.{
        .file = b.path("src/keyword_classify.c"),
        .flags = &.{ "-std=c11", "-w" },
    });
    linkProductionDuoLexer(b, mod);
    mod.link_libc = true;
}

/// SH-03 production dispatch: Idol lexer regenerated from
/// `lib/compiler/lexer.id`. Provides `duo_lexer_tokenize_full`.
/// Keyword classify is the separate generated unit above.
fn linkProductionDuoLexer(b: *std.Build, mod: *std.Build.Module) void {
    mod.addCSourceFile(.{
        .file = b.path("src/lexer_tokenize.c"),
        // The generated lexer artifact carries an executable `main` from the
        // C-backend generator; we link it as a library, so rename that
        // symbol to avoid collision with the Zig test runner / exe root.
        .flags = &.{ "-std=c11", "-w", "-Dmain=duo_lexer_tokenize_main" },
    });
    mod.link_libc = true;
}

/// The direct backend's runtime support, COMPILED FROM ZIG AND CARRIED INSIDE
/// THE COMPILER — the half of "no C backend" that nobody notices.
///
/// Retiring `--backend=c` does not make this compiler C-free while the DIRECT
/// backend still hands C source to clang at link time, which is what it did:
/// `s:has()`, `s:sub()`, `s:find()` and `s:to(i64)` were implemented in
/// `src/idol_str_bootstrap.c`, and `io:read()` / `os.args` / `os.cwd` in
/// `src/idol_io_bootstrap.c`. Both files were appended to the link line, so
/// every direct-backend binary that touched a string was compiled from C.
/// Deleting the emitter while keeping that would only have made the C
/// invisible, which is worse than leaving it visible.
///
/// The ports are `src/idol_str_runtime.zig` and `src/idol_io_runtime.zig`. They
/// are compiled HERE, to objects, and embedded into the compiler by
/// `@embedFile` so that `bin/idol` remains ONE FILE that can be vendored into
/// another tree by copying — the same property the embedded C had, and the
/// reason it was embedded rather than resolved against the source tree.
///
/// TWO OBJECTS, NOT ONE, and that is deliberate. `boot()` in main.zig picks the
/// str unit or the io unit per program, and only the io unit carries the
/// pre-main constructor that sets stdout line-buffered. Merging them into a
/// single object would link that constructor into every string-only program and
/// silently change when its output flushes.
///
/// Built for aarch64-macos regardless of the host: the direct backend emits
/// AArch64 Mach-O and nothing else, so the runtime it links against has exactly
/// one shape. ReleaseFast and a fixed target also keep the bytes deterministic,
/// which is what the content-addressed materialization in main.zig assumes.
fn addDirectRuntimeObjects(b: *std.Build, mod: *std.Build.Module) void {
    const rt_target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    });
    const units = [_][]const u8{ "idol_str_runtime", "idol_io_runtime" };
    inline for (units) |unit| {
        const obj = b.addObject(.{
            .name = unit,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/" ++ unit ++ ".zig"),
                .target = rt_target,
                .optimize = .ReleaseFast,
            }),
        });
        mod.addAnonymousImport(unit ++ ".o", .{ .root_source_file = obj.getEmittedBin() });
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "idol",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    linkProductionKeywordClassify(b, exe.root_module);
    addDirectRuntimeObjects(b, exe.root_module);
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

    const test_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/run_compile_fail_tests.id" });
    test_cmd.setCwd(b.path("."));
    test_cmd.step.dependOn(b.getInstallStep());
    // G11 — the language census ratchet. A number nobody runs is a number that
    // drifts, which is how "no language but Duo" stayed a slogan instead of a
    // list of twelve files.
    const census_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "--backend=c", "scripts/language_census.id" });
    census_cmd.setCwd(b.path("."));
    census_cmd.step.dependOn(b.getInstallStep());
    const census_step = b.step("language-census", "G11: count tracked non-Duo source; ratchets sh/py, js and zig");
    census_step.dependOn(&census_cmd.step);

    // U8 -- `toolchain@{ foreign = ledger | oracle }`. The step above answers
    // how MUCH foreign code there is; this one answers by what RIGHT each file
    // is here. Two licences exist -- bootstrap ledger with a termination
    // condition, or CI oracle -- and anything else is a violation. Rules live in
    // docs/spec/foreign.md, the same no-silent-default mechanism corpus.md uses
    // for .id.
    const foreign_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "--entry", "census", "scripts/census/foreign.id" });
    foreign_cmd.setCwd(b.path("."));
    foreign_cmd.step.dependOn(b.getInstallStep());
    const foreign_step = b.step("foreign-census", "U8: every foreign file classified ledger or oracle; ratchets violations");
    foreign_step.dependOn(&foreign_cmd.step);

    const embed_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "--backend=c", "scripts/embedledger.id" });
    embed_cmd.setCwd(b.path("."));
    embed_cmd.step.dependOn(b.getInstallStep());
    const embed_step = b.step("embed-ledger", "Embedded @c audit; enforce zero sites for self-hosting");
    embed_step.dependOn(&embed_cmd.step);

    // The native census. Same reasoning as G11 one level down: "native 100%"
    // was a slogan because nothing measured it honestly. `duo compile` falls
    // back to the C backend and still reports ok, so only --backend=direct is
    // an answer -- and the ratio has to be over the REACHABLE set, because a
    // compiler proof fixture that exists to drive the C emitter can never be
    // native and counting it turns a 90% ceiling into a 61% failure.
    const native_census_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/native_census.id" });
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
    const abi_matrix_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/abi_matrix.id" });
    abi_matrix_cmd.setCwd(b.path("."));
    abi_matrix_cmd.step.dependOn(b.getInstallStep());
    const abi_matrix_step = b.step("abi-matrix", "differential generated ABI call shapes; ratchets MISCOMPILE_CEILING down");
    abi_matrix_step.dependOn(&abi_matrix_cmd.step);

    // G-D3, the encode half. `abi-matrix` above is a G-D3-shaped gate
    // one level up -- generated shapes, oracle-checked, per row -- and §6 of
    // the encode plan names it as the precedent to extend downward: "Generating
    // ISA property tests per instruction is the same move one level down."
    //
    // `lib/target/arm64.id` is the instruction set as DATA: 45 forms, each
    // a base word plus `field@hi:lo` layout facts, with ONE derived encoder over
    // all of them and no per-instruction code. This step expands every row into
    // 16 operand tuples, hands the assembler text to clang, disassembles the
    // object, and compares 720 words byte for byte. The oracle is the external
    // assembler and never this repository's own encoder -- a generated test
    // that agrees with a wrong descriptor proves nothing.
    //
    // It found two on its first run: `rbit` was the 32-bit form under a ctz
    // lowering that needs 64 (`@ctz(8)` answered 35 natively, 3 in C), and
    // `scvtf` converted from a 32-bit GPR while both callers pass an x
    // register. The gate carries three damaged descriptors as positive controls
    // and exits 3 -- not 0 -- if any of them goes uncaught.
    const isa_fidelity_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/isa_fidelity.id" });
    isa_fidelity_cmd.setCwd(b.path("."));
    isa_fidelity_cmd.step.dependOn(b.getInstallStep());
    const isa_fidelity_step = b.step("isa-fidelity", "G-D3: ARM64 descriptors encode what the oracle assembler encodes");
    isa_fidelity_step.dependOn(&isa_fidelity_cmd.step);

    // §22's capability matrix. §22 answered "what works?" with a
    // Boolean and, for running, with "nothing" -- conservative rather than
    // honest, because a compiler does not implement a program, it carries it
    // some distance up a ladder and the distance is the information. This
    // reports the population of examples/ at each rung from described through
    // canonical. It depends on the install step for the same reason the census
    // does: a matrix measured with yesterday's compiler is a confident report
    // about a build nobody has, and the script refuses to run against one.
    const capability_matrix_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/capability_matrix.id" });
    capability_matrix_cmd.setCwd(b.path("."));
    capability_matrix_cmd.step.dependOn(b.getInstallStep());
    const capability_matrix_step = b.step("capability-matrix", "population of examples/ per capability rung");
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
    const capability_rows_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/capability_rows.id" });
    capability_rows_cmd.setCwd(b.path("."));
    capability_rows_cmd.step.dependOn(b.getInstallStep());
    const capability_rows_step = b.step("capability-rows", "per-CAPABILITY matrix, generated from fixtures");
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
    const runtime_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/runtime_bench.id" });
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

    // C0 law.corpus.zero is the Idol owner; this is an authority-free physical
    // Git-status projection. The same shim guards commits and serialized
    // admission so empty, binary, renamed, case-varied, and untracked .id
    // paths cannot bypass the added-line Idol gate. Delete this bridge only
    // after an executed Idol gate covers staged additions, the anchored
    // committed range, and untracked worktree candidates fail-closed.
    // Parent of the commit that admitted C0 corpus-zero. Comparing from the
    // immutable law-adoption boundary catches a forbidden path hidden in any
    // earlier commit of a multi-commit change, including --no-verify commits.
    const source_zero_cmd = b.addSystemCommand(&.{
        "./.githooks/pre-commit",
        "source-zero",
        "ad8a9c6eb8b55f724c7b914639be3ba6f76c0507",
    });
    source_zero_cmd.setCwd(b.path("."));

    const no_ansi_reports_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/assert_no_ansi_reports.id" });
    no_ansi_reports_cmd.setCwd(b.path("."));
    no_ansi_reports_cmd.step.dependOn(b.getInstallStep());
    const no_ansi_reports_step = b.step("no-ansi-reports", "Assert report ANSI/no-color styling contract");
    no_ansi_reports_step.dependOn(&no_ansi_reports_cmd.step);
    const report_styling_step = b.step("report-styling", "Assert rich and no-color test report styling");
    report_styling_step.dependOn(&no_ansi_reports_cmd.step);
    test_step.dependOn(&no_ansi_reports_cmd.step);

    const gpu_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/run_gpu_benchmark.id" });
    gpu_bench_cmd.setCwd(b.path("."));
    gpu_bench_cmd.step.dependOn(b.getInstallStep());
    const gpu_bench_step = b.step("gpu-bench", "Run Duo vs GPU Metal benchmark");
    gpu_bench_step.dependOn(&gpu_bench_cmd.step);
    test_step.dependOn(&gpu_bench_cmd.step);

    const bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/run_benchmark.id" });
    bench_cmd.setCwd(b.path("."));
    bench_cmd.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run Duo vs C benchmark suite");
    bench_step.dependOn(&bench_cmd.step);

    const cross_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/run_cross_benchmark.id" });
    cross_bench_cmd.setCwd(b.path("."));
    cross_bench_cmd.step.dependOn(b.getInstallStep());
    const cross_bench_step = b.step("cross-bench", "Run cross-language benchmark (Duo vs C vs Lua vs LuaJIT)");
    cross_bench_step.dependOn(&cross_bench_cmd.step);

    const wasm_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/run_wasm_benchmark.id" });
    wasm_bench_cmd.setCwd(b.path("."));
    wasm_bench_cmd.step.dependOn(b.getInstallStep());
    const wasm_bench_step = b.step("wasm-bench", "Run WASM runtime benchmark (wasmtime, wazero, wasm3, iwasm, wasmer, spin)");
    wasm_bench_step.dependOn(&wasm_bench_cmd.step);

    // ── wasm evidence firewall (tools/wasm) ─────────────────────────────────
    // Wasm is admitted only through direct-native artifacts. The old route
    // built both subject and harness with the retired C backend into shared
    // zig-out paths; a stale binary could therefore outlive its source and
    // every reported row was non-authoritative. Build cache outputs below are
    // private to the exact inputs, and any direct-native refusal is the gate's
    // outcome rather than permission to ask a retired realization.
    //
    // This bounded shell bridge only transports revision/hash/oracle evidence
    // while direct Idol lacks those host projections. It owns no Wasm meaning.
    // Delete it when the tracked direct-native harness can obtain the same
    // facts itself (law.bridge.death).
    const wasm_evidence_cmd = b.addSystemCommand(&.{
        "sh", "-eu", "-c",
        \\build_zig_version=$1
        \\build_optimize=$2
        \\revision=$(git rev-parse HEAD)
        \\dirty=$(git status --porcelain=v1 --untracked-files=all)
        \\if [ -n "$dirty" ]; then dirty_state=dirty; else dirty_state=clean; fi
        \\dirty_hash=$(git status --porcelain=v1 --untracked-files=all | shasum -a 256 | cut -d ' ' -f 1)
        \\engine_hash=$(shasum -a 256 tools/wasm/src/engine.id | cut -d ' ' -f 1)
        \\wasi_abi_hash=$(shasum -a 256 tools/wasm/src/wasm/wasi_abi.id | cut -d ' ' -f 1)
        \\jit_hash=$(shasum -a 256 lib/jit.id | cut -d ' ' -f 1)
        \\harness_hash=$(shasum -a 256 tools/wasm/test/conform.id | cut -d ' ' -f 1)
        \\compiler_hash=$(shasum -a 256 zig-out/bin/idol | cut -d ' ' -f 1)
        \\printf 'wasm-evidence subject_revision=%s evidence_revision=%s dirty=%s dirty_sha256=%s\n' "$revision" "$revision" "$dirty_state" "$dirty_hash"
        \\printf 'wasm-evidence build_zig_version=%s compiler_optimize=%s embedded_direct_runtime_optimize=ReleaseFast\n' "$build_zig_version" "$build_optimize"
        \\printf 'wasm-evidence compiler_binary_sha256=%s\n' "$compiler_hash"
        \\printf 'wasm-evidence engine_source_sha256=%s harness_source_sha256=%s\n' "$engine_hash" "$harness_hash"
        \\printf 'wasm-evidence wasi_abi_source_sha256=%s jit_source_sha256=%s\n' "$wasi_abi_hash" "$jit_hash"
        \\printf 'wasm-evidence modes=interpreter,forced-jit,default,fallback outcome=pending-preflight\n'
        \\wart_pin=ca2b0b9c0fb8c397987be2b4475fd1ccfe4d150b
        \\if [ -z "${WART_ORACLE_REPO:-}" ]; then
        \\  printf 'CAPABILITY BLOCKED wart-oracle-unconfigured expected_revision=%s role=test-only\n' "$wart_pin" >&2
        \\  exit 2
        \\fi
        \\if [ ! -d "$WART_ORACLE_REPO/.git" ]; then
        \\  printf 'CAPABILITY BLOCKED wart-oracle-source-missing path=%s expected_revision=%s\n' "$WART_ORACLE_REPO" "$wart_pin" >&2
        \\  exit 2
        \\fi
        \\wart_repo=$(cd "$WART_ORACLE_REPO" && pwd -P)
        \\wart_revision=$(git -C "$wart_repo" rev-parse HEAD 2>/dev/null || true)
        \\if [ "$wart_revision" != "$wart_pin" ]; then
        \\  printf 'CAPABILITY BLOCKED wart-oracle-revision expected=%s actual=%s\n' "$wart_pin" "${wart_revision:-missing}" >&2
        \\  exit 2
        \\fi
        \\wart_dirty=$(git -C "$wart_repo" status --porcelain=v1 --untracked-files=all)
        \\if [ -n "$wart_dirty" ]; then
        \\  printf 'CAPABILITY BLOCKED wart-oracle-dirty revision=%s\n' "$wart_revision" >&2
        \\  exit 2
        \\fi
        \\wart_bin=${WART_ORACLE_BIN:-$wart_repo/zig-out/bin/wart}
        \\case "$wart_bin" in "$wart_repo"/*) ;; *) printf 'CAPABILITY BLOCKED wart-oracle-unattributed binary=%s\n' "$wart_bin" >&2; exit 2 ;; esac
        \\if [ ! -x "$wart_bin" ]; then
        \\  printf 'CAPABILITY BLOCKED wart-oracle-binary-missing path=%s revision=%s\n' "$wart_bin" "$wart_revision" >&2
        \\  exit 2
        \\fi
        \\wart_version=$("$wart_bin" --version)
        \\wart_hash=$(shasum -a 256 "$wart_bin" | cut -d ' ' -f 1)
        \\wart_provenance=${WART_ORACLE_PROVENANCE:-$wart_bin.provenance}
        \\if [ ! -f "$wart_provenance" ]; then
        \\  printf 'CAPABILITY BLOCKED wart-oracle-provenance-missing path=%s\n' "$wart_provenance" >&2
        \\  exit 2
        \\fi
        \\wart_provenance_revision=$(sed -n 's/^revision=//p' "$wart_provenance")
        \\wart_provenance_hash=$(sed -n 's/^binary_sha256=//p' "$wart_provenance")
        \\if [ "$wart_provenance_revision" != "$wart_revision" ] || [ "$wart_provenance_hash" != "$wart_hash" ]; then
        \\  printf 'CAPABILITY BLOCKED wart-oracle-provenance-mismatch revision=%s binary_sha256=%s\n' "$wart_revision" "$wart_hash" >&2
        \\  exit 2
        \\fi
        \\wart_provenance_sha=$(shasum -a 256 "$wart_provenance" | cut -d ' ' -f 1)
        \\if ! oracle=$(command -v wasmtime); then
        \\  printf 'CAPABILITY BLOCKED wasmtime-oracle-missing expected_version=47.0.3\n' >&2
        \\  exit 2
        \\fi
        \\oracle_version=$("$oracle" --version)
        \\case "$oracle_version" in
        \\  "wasmtime 47.0.3 "*) ;;
        \\  *) printf 'CAPABILITY BLOCKED oracle-pin expected=47.0.3 actual=%s\n' "$oracle_version" >&2; exit 2 ;;
        \\esac
        \\oracle_hash=$(shasum -a 256 "$oracle" | cut -d ' ' -f 1)
        \\printf 'wasm-evidence oracle=wasmtime version=%s binary_sha256=%s\n' "$oracle_version" "$oracle_hash"
        \\printf 'wasm-evidence oracle=wart revision=%s version=%s binary_sha256=%s provenance_sha256=%s role=test-only dynamic_competitor=no\n' "$wart_revision" "$wart_version" "$wart_hash" "$wart_provenance_sha"
        \\printf 'wasm-evidence preflight=pass outcome=pending-direct-native\n'
        ,
        "wasm-evidence",
        builtin.zig_version_string,
        @tagName(optimize),
    });
    wasm_evidence_cmd.setCwd(b.path("."));
    wasm_evidence_cmd.step.dependOn(b.getInstallStep());

    const wasm_engine_cmd = b.addSystemCommand(&.{
        "sh",          "-eu", "-c",
        \\if ! ./zig-out/bin/idol compile tools/wasm/src/engine.id --backend=direct --emit exe -o "$1"; then
        \\  printf 'CAPABILITY BLOCKED direct-native-engine source=tools/wasm/src/engine.id\n' >&2
        \\  exit 1
        \\fi
        ,
        "wasm-engine",
    });
    const wasm_engine_bin = wasm_engine_cmd.addOutputFileArg("wasm-engine");
    wasm_engine_cmd.addFileInput(exe.getEmittedBin());
    wasm_engine_cmd.addFileInput(b.path("tools/wasm/src/engine.id"));
    wasm_engine_cmd.addFileInput(b.path("tools/wasm/src/wasm/wasi_abi.id"));
    wasm_engine_cmd.addFileInput(b.path("lib/jit.id"));
    wasm_engine_cmd.setCwd(b.path("."));
    wasm_engine_cmd.step.dependOn(&wasm_evidence_cmd.step);

    const wasm_engine_artifact_evidence_cmd = b.addSystemCommand(&.{
        "sh", "-eu", "-c",
        \\engine_hash=$(shasum -a 256 "$1" | cut -d ' ' -f 1)
        \\printf 'wasm-evidence artifact=direct-native-engine binary_sha256=%s\n' "$engine_hash"
        ,
        "wasm-engine-artifact",
    });
    wasm_engine_artifact_evidence_cmd.addFileArg(wasm_engine_bin);
    wasm_engine_artifact_evidence_cmd.setCwd(b.path("."));
    wasm_engine_artifact_evidence_cmd.step.dependOn(&wasm_engine_cmd.step);

    const wasm_test_build_cmd = b.addSystemCommand(&.{
        "sh",           "-eu", "-c",
        \\if ! ./zig-out/bin/idol compile tools/wasm/test/conform.id --backend=direct --emit exe -o "$1"; then
        \\  printf 'CAPABILITY BLOCKED direct-native-harness source=tools/wasm/test/conform.id\n' >&2
        \\  exit 1
        \\fi
        ,
        "wasm-harness",
    });
    const wasm_test_bin = wasm_test_build_cmd.addOutputFileArg("wasm-conform");
    wasm_test_build_cmd.addFileInput(exe.getEmittedBin());
    wasm_test_build_cmd.addFileInput(b.path("tools/wasm/test/conform.id"));
    wasm_test_build_cmd.setCwd(b.path("."));
    wasm_test_build_cmd.step.dependOn(&wasm_engine_artifact_evidence_cmd.step);

    const wasm_harness_artifact_evidence_cmd = b.addSystemCommand(&.{
        "sh", "-eu", "-c",
        \\harness_hash=$(shasum -a 256 "$1" | cut -d ' ' -f 1)
        \\printf 'wasm-evidence artifact=direct-native-harness binary_sha256=%s\n' "$harness_hash"
        ,
        "wasm-harness-artifact",
    });
    wasm_harness_artifact_evidence_cmd.addFileArg(wasm_test_bin);
    wasm_harness_artifact_evidence_cmd.setCwd(b.path("."));
    wasm_harness_artifact_evidence_cmd.step.dependOn(&wasm_test_build_cmd.step);

    const wasm_test_cmd = b.addSystemCommand(&.{
        "sh",        "-eu", "-c",
        \\DUO_WASM_BIN="$1" WASMTIME_VERSION=47.0.3 "$2"
        ,
        "wasm-test",
    });
    wasm_test_cmd.addFileArg(wasm_engine_bin);
    wasm_test_cmd.addFileArg(wasm_test_bin);
    wasm_test_cmd.setCwd(b.path("tools/wasm"));
    wasm_test_cmd.step.dependOn(&wasm_harness_artifact_evidence_cmd.step);

    // The deliberate comparator sabotage must be observed as harness failure
    // (exit 3). A zero here means the damage control cannot damage the proof.
    const wasm_damage_cmd = b.addSystemCommand(&.{
        "sh",               "-eu", "-c",
        \\set +e
        \\DUO_WASM_DAMAGE=comparator DUO_WASM_BIN="$1" WASMTIME_VERSION=47.0.3 "$2"
        \\status=$?
        \\set -e
        \\if [ "$status" -ne 3 ]; then
        \\  printf 'CONTROL FAIL: comparator sabotage returned %s, expected 3\n' "$status" >&2
        \\  exit 1
        \\fi
        \\printf 'damage-control comparator=failed-as-required\n'
        ,
        "wasm-test-damage",
    });
    wasm_damage_cmd.addFileArg(wasm_engine_bin);
    wasm_damage_cmd.addFileArg(wasm_test_bin);
    wasm_damage_cmd.setCwd(b.path("tools/wasm"));
    wasm_damage_cmd.step.dependOn(&wasm_test_cmd.step);

    const wasm_test_step = b.step("wasm-test", "direct-native Wasm evidence: pinned oracle, explicit modes and damage controls");
    wasm_test_step.dependOn(&wasm_damage_cmd.step);

    const ml_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/run_ml_benchmark.id" });
    ml_bench_cmd.setCwd(b.path("."));
    ml_bench_cmd.step.dependOn(b.getInstallStep());
    const ml_bench_step = b.step("ml-bench", "Run ML benchmark suite (Duo vs C)");
    ml_bench_step.dependOn(&ml_bench_cmd.step);

    // `scripts/run_honest_benchmark.sh` does not exist and has not for some
    // time — the Duo port is tracked and the shell file is not, so this step
    // was invoking bash on a missing path. Repointed at the file that is there.
    const honest_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/run_honest_benchmark.id" });
    honest_bench_cmd.setCwd(b.path("."));
    honest_bench_cmd.step.dependOn(b.getInstallStep());
    const honest_bench_step = b.step("honest-bench", "Run honest benchmark (no precomputation, runtime inputs)");
    honest_bench_step.dependOn(&honest_bench_cmd.step);

    const compile_size_bench_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/run_compile_size_benchmark.id" });
    compile_size_bench_cmd.setCwd(b.path("."));
    compile_size_bench_cmd.step.dependOn(b.getInstallStep());
    const compile_size_bench_step = b.step("compile-size-bench", "Track compile time and binary size vs C");
    compile_size_bench_step.dependOn(&compile_size_bench_cmd.step);

    // Public safety pre-scan
    const public_safety_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/public_safety_scan.id" });
    public_safety_cmd.setCwd(b.path("."));
    const public_safety_step = b.step("public-safety", "Scan tracked files for secrets and personal paths");
    public_safety_step.dependOn(&public_safety_cmd.step);

    // One source, N projection targets, compared on a stdout fingerprint rather
    // than exit status alone. native-differential compares only exit status (it
    // sends stdout to /dev/null), so two backends that print different answers
    // "agree" there as long as both exit 0.
    const semantic_harness_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/semantic_harness.id" });
    semantic_harness_cmd.setCwd(b.path("."));
    semantic_harness_cmd.step.dependOn(b.getInstallStep());
    const semantic_harness_step = b.step("semantic-harness", "Every projection target must agree on stdout, not just exit status");
    semantic_harness_step.dependOn(&semantic_harness_cmd.step);

    const repo_hygiene_cmd = b.addSystemCommand(&.{ "./tools/node/dev/repo-hygiene" });
    repo_hygiene_cmd.setCwd(b.path("."));
    const repo_hygiene_step = b.step("repo-hygiene", "forbidden root artifacts and tracked agent noise");
    repo_hygiene_step.dependOn(&repo_hygiene_cmd.step);

    const pathcensus_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "gate/census.id" });
    pathcensus_cmd.setCwd(b.path("."));
    pathcensus_cmd.step.dependOn(b.getInstallStep());
    const pathcensus_step = b.step("path-census", "law.path.name: tracked name debt census");
    pathcensus_step.dependOn(&pathcensus_cmd.step);

    const pathgate_cmd = b.addSystemCommand(&.{
        "sh", "-c",
        \\tmp=$(mktemp -t idolpath) && printf '%s\n' graph.id > "$tmp" && dif=$(mktemp -t idolname) && printf '%s\n' '--- a/x.id' '+++ b/x.id' '@@ -0,0 +1,1 @@' '+bad = nativebackend' > "$dif" && IDOLPATHLIST="$tmp" IDOLNAMEDIFF="$dif" ./zig-out/bin/idol run gate/path.id; rc=$?; rm -f "$tmp" "$dif"; exit $rc
    });
    pathgate_cmd.setCwd(b.path("."));
    pathgate_cmd.step.dependOn(b.getInstallStep());
    const pathgate_step = b.step("path-gate", "law.path.name: gate/path admission firewall");
    pathgate_step.dependOn(&pathgate_cmd.step);

    const world_launch_cmd = b.addSystemCommand(&.{ "sh", "gate/world-launch.sh" });
    world_launch_cmd.setCwd(b.path("."));
    world_launch_cmd.setEnvironmentVariable("IDOL_BUILD_MODE", @tagName(optimize));
    world_launch_cmd.step.dependOn(b.getInstallStep());
    const world_launch_step = b.step("world-launch", "launcher world admission and cache separation");
    world_launch_step.dependOn(&world_launch_cmd.step);

    const defaults_cmd = b.addSystemCommand(&.{ "sh", "gate/defaults.sh" });
    defaults_cmd.setCwd(b.path("."));
    defaults_cmd.setEnvironmentVariable("IDOL_BUILD_MODE", @tagName(optimize));
    defaults_cmd.step.dependOn(b.getInstallStep());
    const defaults_step = b.step("defaults-gate", "census function and descriptor defaults across parse, check, direct, and run");
    defaults_step.dependOn(&defaults_cmd.step);

    // tree-sitter-coverage -- section 19's editor front-end, measured.
    // Runs the generator (failing if it exits non-zero, which the nvim setup
    // script used to swallow), parses every tracked .id file, and ratchets off
    // a ceiling on UNRECOGNISED files. It positive-controls its own detector on
    // every run against a valid file and a deliberately broken one, because a
    // coverage counter that cannot fail reports a number that proves nothing.
    const ts_coverage_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/tree_sitter_coverage.id" });
    ts_coverage_cmd.setCwd(b.path("."));
    const ts_coverage_step = b.step("tree-sitter-coverage", "tree-sitter generates, and recognises a ratcheted share of the .id corpus (GAP-049)");
    ts_coverage_step.dependOn(&ts_coverage_cmd.step);

    // "the host": tree-sitter is "a generated grammar projection
    // (output, never authored)". ext/tree-sitter-duo/grammar.js is PARTLY
    // that now -- everything outside its @@residue markers is emitted by
    // scripts/treesitter_emit.id. This step regenerates and fails unless the
    // result is byte-identical to the tracked file, which is the only thing
    // that separates a generated artifact from an authored one with a banner.
    // It also prints the authored residue line count, which is the number
    // GAP-049 is measured by.
    const ts_projection_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/treesitter_emit.id" });
    ts_projection_cmd.setCwd(b.path("."));
    ts_projection_cmd.setEnvironmentVariable("TSEMIT_CHECK", "1");
    ts_projection_cmd.step.dependOn(b.getInstallStep());
    const ts_projection_step = b.step("treesitter-projection", "grammar.js regenerates byte-identically from scripts/treesitter_emit.id (GAP-049)");
    ts_projection_step.dependOn(&ts_projection_cmd.step);

    const ftcftw_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/ledger/ftcftw.id" });
    ftcftw_cmd.setCwd(b.path("."));
    ftcftw_cmd.step.dependOn(b.getInstallStep());
    const ftcftw_step = b.step("ftcftw-ledger", "law.project.ftcftw: Idol-only native > c-equivalent > wasm evidence chain index");
    ftcftw_step.dependOn(&ftcftw_cmd.step);

    // tail-slot -- gap[104]. A block's final expression lives in
    // `blk.tail_expr`, and in dnir_lower only the RETURN path ever read that
    // field, so a branch body or a loop body -- both lowered with
    // `allow_return = false` -- dropped its last statement on the floor. The
    // direct backend is what `duo run` uses, so every conditional print, every
    // error path and every accumulate-then-emit loop was silent by default
    // while `--backend=c` was correct. A step of its own rather than an
    // audit100 row because it COMPILES AND RUNS four programs through both
    // backends and reads their stdout BY VALUE -- the defect survived three
    // wrong diagnoses precisely because each probed control flow with the
    // thing that was broken.
    const tailslot_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/tailslot.id" });
    tailslot_cmd.setCwd(b.path("."));
    tailslot_cmd.step.dependOn(b.getInstallStep());
    const tailslot_step = b.step("tail-slot", "gap[104]: a non-answering block's tail expression runs, and matches the C backend");
    tailslot_step.dependOn(&tailslot_cmd.step);

    // audit100 -- CLAUDE.md section 1's deny table, executable. It scans the
    // canonical partition of docs/spec/corpus.md only, because compile_fail
    // fixtures are SUPPOSED to contain the denied text, and it ratchets off
    // measured budgets rather than gating at zero, because a gate that is red
    // on the day it ships is a gate people learn to skip.
    const audit100_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/audit100.id" });
    audit100_cmd.setCwd(b.path("."));
    audit100_cmd.step.dependOn(b.getInstallStep());
    const audit100_step = b.step("audit100", "deny table over the canonical .id corpus; ratchets each row");
    audit100_step.dependOn(&audit100_cmd.step);

    // role-scan is GONE, and this note is here so the next reader does not go
    // looking for it. gaps/GAP-078.md: two role taxonomies landed in this tree
    // on the same day and disagreed -- on `:`, on the count, on whether an
    // ordinary binding has a hue, on the spelling of the string role, and on
    // whether the section 0g fine splits are roles. Two generators for one
    // legend means whichever a front end picks, the other convicts it, and the
    // two coverage numbers measured different quantities. The ruling merged
    // them into ONE taxonomy and DELETED `scripts/role_scan.id` rather than
    // parking it beside the survivor. Its corpus was not deleted with it: the
    // seven fixtures under fixtures/highlight/*.id and their span sidecars are
    // now measured by `highlight-corpus` below, in the surviving vocabulary.
    //
    // highlight-corpus -- CLAUDE.md section 0d, executable. Highlighting is a
    // PROJECTION OF THE GRAPH, not a lexer, and the only way to tell those two
    // apart from outside is a corpus containing the glyphs idol overloads: `:`
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
    // separately because it is the bar coverage is not.
    const highlight_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/highlight.id" });
    highlight_cmd.setCwd(b.path("."));
    highlight_cmd.step.dependOn(b.getInstallStep());
    const highlight_step = b.step("highlight-corpus", "the golden role corpus, totality, the H-1 proofs by value, and specificity; ratchets");
    highlight_step.dependOn(&highlight_cmd.step);

    // U1 -- `std@{ ambient = false }`, executable. The one
    // charter row that is effective immediately rather than at 0.1, so it is a
    // step rather than a plan. It ratchets off a measured baseline for the same
    // reason audit100 does: std has ambient reach today, and a gate that is red
    // on the day it ships is a gate people learn to skip. The number has to be
    // VISIBLE and fall; it does not have to be zero tomorrow.
    const capability_scan_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/capability_scan.id" });
    capability_scan_cmd.setCwd(b.path("."));
    capability_scan_cmd.step.dependOn(b.getInstallStep());
    const capability_scan_step = b.step("capability-scan", "U1: ambient fs/net/clock/rand/proc/fault reach in lib/std; ratchets");
    capability_scan_step.dependOn(&capability_scan_cmd.step);

    // APPLY-ONE -- c0 section 43 `law.brace` and section 44 `law.apply.one`.
    // A step of its own because the positive fixture and the negative twin are
    // only evidence when they are read TOGETHER: either alone passes under a
    // compiler that had picked one reading for every brace, which is the state
    // gap[088] measured and gap[092] still carries. The runner also checks the
    // OWED row in the direction it currently fails, so the gate goes red the day
    // descriptor application starts working -- a gate that cannot notice its own
    // gap closing is decoration.
    const apply_one_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/applyone.id" });
    apply_one_cmd.setCwd(b.path("."));
    apply_one_cmd.step.dependOn(b.getInstallStep());
    const apply_one_step = b.step("apply-one", "c0 section 43/44: one brace form, three outcomes; descriptor row owed by gap[092]");
    apply_one_step.dependOn(&apply_one_cmd.step);

    // RECOGNITION -- the AUDIT v4 row, executable. It is a
    // step of its own rather than a row inside audit100 because the whole
    // finding is that `math.` is TWO rules: pure ops that want a value edge and
    // carry no capability, and `math.random`, which is ambient authority and is
    // the ENTIRE `rand` class the capability scan ratchets. One averaged budget
    // would hide that. It also probes its own two blockers live -- the value
    // edge is built AND RUN, never merely `check`ed, because `duo check` exits
    // 0 on `x:abs()` and only codegen rejects it.
    const recognition_scan_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/recognition_scan.id" });
    recognition_scan_cmd.setCwd(b.path("."));
    recognition_scan_cmd.step.dependOn(b.getInstallStep());
    const recognition_scan_step = b.step("recognition-scan", "s0a: std.mem/std.fmt/std.math and bare math. in lib/std; ratchets");
    recognition_scan_step.dependOn(&recognition_scan_cmd.step);

    // gap[080]. `scripts/bootstrap_scan.id` has been in the tree, working and
    // passing, with NO BUILD STEP -- so nothing ever ran it. gaps/GAP-080.md
    // says "Landed with this gap: `zig build bootstrap-scan`"; the script
    // landed and the step did not, which is the same class of defect the gap
    // itself is about: `src/*.zig` is the one corpus the deny table cannot
    // see, and the instrument built to see it was itself invisible.
    //
    // audit100 walks the canonical .id partition and excludes the bootstrap
    // ledger from every deny row, so the compiler -- the artifact that
    // enforces the law on every other file -- was unmeasured. This row
    // ratchets DOWN over tracked src/*.zig only.
    const bootstrap_scan_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/bootstrap_scan.id" });
    bootstrap_scan_cmd.setCwd(b.path("."));
    bootstrap_scan_cmd.step.dependOn(b.getInstallStep());
    const bootstrap_scan_step = b.step("bootstrap-scan", "gap[080]: the deny table over src/*.zig, the corpus audit100 excludes; ratchets");
    bootstrap_scan_step.dependOn(&bootstrap_scan_cmd.step);

    const semantic_architecture_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "--backend=c", "gate/architecture.id" });
    semantic_architecture_cmd.setCwd(b.path("."));
    semantic_architecture_cmd.step.dependOn(b.getInstallStep());
    const semantic_architecture_step = b.step("semantic-architecture", "C0 §65: syntax faces erase into semantic relations, facts and demand; debt ratchets");
    semantic_architecture_step.dependOn(&semantic_architecture_cmd.step);

    // gap[076]. The gap allocator's mkdir(2) is atomic within ONE filesystem
    // view, and parallel agents here work in git worktrees, which are several.
    // Both of its inputs used to be worktree-local, so two agents mkdir'd two
    // different paths and both won. Reservations now live under
    // --git-common-dir, which every worktree shares.
    //
    // Report mode prints the RESOLVED LEDGER PATH rather than a verdict, and
    // that is the whole point: a silent fallback to the worktree-local ledger
    // would keep colliding while reporting success, so the path is the only
    // thing that tells the two apart. Read-only -- it allocates nothing.
    const gapalloc_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/gapalloc.id" });
    gapalloc_cmd.setCwd(b.path("."));
    gapalloc_cmd.step.dependOn(b.getInstallStep());
    const gapalloc_step = b.step("gapalloc", "gap[076]: resolved gap-reservation ledger path, high-water mark across ALL refs, next number");
    gapalloc_step.dependOn(&gapalloc_cmd.step);

    // The first sixty seconds of a new user's life, gated. src/build_framework.zig's
    // tests drive parser+sema in-process and stayed green while `duo init` emitted a
    // src/main.id that `duo check`, `duo build` and `duo run` all rejected. Only a
    // gate that shells the real CLI into a real scratch directory can see that.
    const init_build_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/init_build_smoke.id" });
    init_build_cmd.setCwd(b.path("."));
    init_build_cmd.step.dependOn(b.getInstallStep());
    const init_build_step = b.step("init-build-smoke", "duo init -> check -> build -> run -> test on a clean directory");
    init_build_step.dependOn(&init_build_cmd.step);

    // U2 -- `build@deterministic`. The step above is its
    // narrow ancestor and stays: it rebuilds into the SAME cache at the SAME
    // path, which a warm cache satisfies by copying rather than recompiling.
    // This one builds twice into two prefixes with two caches, so neither
    // build can see the other's output, and it diagnoses a divergence rather
    // than only reporting one. It never touches zig-out. Two full builds -- not
    // a tier-0 gate.
    const determinism_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/build_determinism.id" });
    determinism_cmd.setCwd(b.path("."));
    determinism_cmd.step.dependOn(b.getInstallStep());
    const determinism_step = b.step("build-determinism", "U2: two independent builds, byte-identical artifacts; names the divergence source");
    determinism_step.dependOn(&determinism_cmd.step);

    const repro_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/reproducibility_smoke.id" });
    repro_cmd.setCwd(b.path("."));
    const repro_step = b.step("reproducibility-smoke", "WP-13: ReleaseFast compiler binary identity across clean rebuilds");
    repro_step.dependOn(&repro_cmd.step);

    const native_module_barrier = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_barrier_checks.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"native_barrier_checks:"},
    });
    const run_native_module_barrier = b.addRunArtifact(native_module_barrier);

    const native_module_target = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/target_model.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_native_module_target = b.addRunArtifact(native_module_target);

    const native_module_proof = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/proof_carrying.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"seed claims"},
    });
    const run_native_module_proof = b.addRunArtifact(native_module_proof);

    const native_module_step = b.step("native-module-smoke", "native_barrier_checks + target_model + catalog unit tests (cross-platform)");
    native_module_step.dependOn(&run_native_module_barrier.step);
    native_module_step.dependOn(&run_native_module_target.step);
    native_module_step.dependOn(&run_native_module_proof.step);

    const native_backend_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_backend.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"WP-04"},
    });
    linkProductionKeywordClassify(b, native_backend_tests.root_module);
    const run_native_backend_tests = b.addRunArtifact(native_backend_tests);
    // Exercises the LIVE native backend over src/native_backend.zig. The old
    // consumer, the deleted catalog gate, ran the same coverage before the
    // catalog apparatus was retired.
    test_step.dependOn(&run_native_backend_tests.step);

    const native_diff_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/native_differential.id" });
    native_diff_cmd.step.dependOn(b.getInstallStep());
    native_diff_cmd.setCwd(b.path("."));
    const native_diff_step = b.step("native-differential", "Direct ARM64 backend must agree with the C backend on the native corpus");
    native_diff_step.dependOn(&native_diff_cmd.step);

    // §22's generated capability table. It reads the SAME corpus
    // native-differential gates and reports the whole ladder — described,
    // parsed, checked, C path, direct-native, differentially proven, canonical
    // — by running the compiler at each rung rather than by asserting a list.
    // It is a report, not a second gate: it fails only when it could not have
    // measured anything.
    const capability_table_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/capability_table.id" });
    capability_table_cmd.step.dependOn(b.getInstallStep());
    capability_table_cmd.setCwd(b.path("."));
    const capability_table_step = b.step("capability-table", "derive the described->canonical ladder from the native corpus");
    capability_table_step.dependOn(&capability_table_cmd.step);

    // constitution §21 `law.identity.three` + `law.dedup`, gap[103]. The
    // relation store keyed every edge on a descriptor's TEXT, which is wrong
    // in both directions the moment packages, renames, versions or private
    // descriptors exist. Two rows of checks, because the failure has two very
    // different shapes: the fixtures pin SER and the printed answer BY VALUE,
    // and a scan pins the quarantine — resolving a spelling is the one place a
    // byte comparison is correct, and it lives in `Names`. The scan's zero
    // carries its own positive control, because a blind scanner also reads 0.
    const relation_id_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/proof/relation.id" });
    relation_id_cmd.step.dependOn(b.getInstallStep());
    relation_id_cmd.setCwd(b.path("."));
    const relation_id_step = b.step("relation-id", "constitution §21: relation-store semantic identity — SER by value + the byte-comparison quarantine");
    relation_id_step.dependOn(&relation_id_cmd.step);

    // constitution §46 `law.nominal`, second clause: "a nominal descriptor over
    // a primitive costs no boxing". The retained value fixture proves the
    // MEANING — 914436 cannot come out of a `feet` that lost its descriptor —
    // and proves nothing at all about the COST, because a boxed double adds
    // just as correctly. This gate reads the emitted C and carries its own
    // positive control: a program that boxes must trip the same predicate, or
    // the gate reports FAIL and no verdict.
    const nominal_zero_cost_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/nominal_zero_cost.id" });
    nominal_zero_cost_cmd.step.dependOn(b.getInstallStep());
    nominal_zero_cost_cmd.setCwd(b.path("."));
    const nominal_zero_cost_step = b.step("nominal-zero-cost", "constitution §46: a nominal descriptor costs no box, read off the emitted C");
    nominal_zero_cost_step.dependOn(&nominal_zero_cost_cmd.step);

    // Twenty MUNDANE programs plus one fixture per numerics/text row.
    // The boring set ratchets a passing count; the table set asserts MEASURED
    // behaviour, so it is a change detector rather than a conformance claim.
    const boring_corpus_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/boring_corpus.id" });
    boring_corpus_cmd.step.dependOn(b.getInstallStep());
    boring_corpus_cmd.setCwd(b.path("."));
    const boring_corpus_step = b.step("boring-corpus", "everyday programs + the measured numerics/text pages, ratcheted");
    boring_corpus_step.dependOn(&boring_corpus_cmd.step);

    // GAP-081: the conversion edge, by VALUE. Both faces, both lowerings, and
    // the input that used to answer 0 — a conversion that compiles and reports
    // 0 for "abc" is the failure mode this tree already paid for once, so
    // "17 -> 17" is only half of what this asserts.
    const convert_proof_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/proof/convert.id" });
    convert_proof_cmd.step.dependOn(b.getInstallStep());
    convert_proof_cmd.setCwd(b.path("."));
    const convert_proof_step = b.step("convert-proof", "GAP-081: str -> i64 in both faces and both lowerings, and a refusal on non-numeric input");
    convert_proof_step.dependOn(&convert_proof_cmd.step);

    // The canonicalizer itself, DRY RUN. It reports what it would rewrite and
    // writes nothing; `CONVERTCANON_APPLY=1` is the only thing that writes.
    const convert_canon_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/convert_canon.id" });
    convert_canon_cmd.step.dependOn(b.getInstallStep());
    convert_canon_cmd.setCwd(b.path("."));
    const convert_canon_step = b.step("convert-canon", "§17: rewrite to(str) sites to the receiver face, witnessed (dry run)");
    convert_canon_step.dependOn(&convert_canon_cmd.step);

    // GAP-080 / GAP-085: the deny table over src/*.zig, which audit100 cannot
    // see. Four ratcheting rows, all running DOWN. The `assume` row is §3
    // MEASUREMENT HONESTY made a number — a live `use_*` flag with no
    // `verify_*` companion — and exists so the eighteenth arrives read.
    //
    // The SCRIPT has existed since c8d6e06 and this STEP did not, so GAP-085
    // records the row as landed while nothing ran it. Both exit directions
    // checked before wiring, per gap[070]: PASS exits 0, and a lowered budget
    // exits 1 after printing `!! assume 17 1`.
    // DEDUP on merge: two agents independently found `bootstrap-scan` was a
    // script with no build step and each wired it. The gap[080] wiring above
    // is kept; this one is removed. The duplicate discovery is the evidence
    // that a phantom gate is findable — see the merge commit.

    // GAP-075: std.fs.remove, by VALUE, both directions. The fixture gap[075]
    // owed and gap[100] rung 2 cited as already existing — it never did, under
    // either spelling. Every assertion reads the FILESYSTEM, because the bug
    // was a wrapper reporting success for a removal that did not happen, and
    // the return value alone could not tell the two apart.
    const fs_remove_proof_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/proof/remove.id" });
    fs_remove_proof_cmd.step.dependOn(b.getInstallStep());
    fs_remove_proof_cmd.setCwd(b.path("."));
    const fs_remove_proof_step = b.step("fs-remove-proof", "GAP-075: fs.remove verified against the filesystem in both directions");
    fs_remove_proof_step.dependOn(&fs_remove_proof_cmd.step);

    // GAP-100 rung 0: the same by-value discipline for mkdir / mkdirall / copy.
    // Written earlier and never wired, so it had not run in CI at all.
    const fs_mkdir_proof_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/proof/mkdir.id" });
    fs_mkdir_proof_cmd.step.dependOn(b.getInstallStep());
    fs_mkdir_proof_cmd.setCwd(b.path("."));
    const fs_mkdir_proof_step = b.step("fs-mkdir-proof", "GAP-100 rung 0: mkdir, mkdirall and copy verified against the filesystem");
    fs_mkdir_proof_step.dependOn(&fs_mkdir_proof_cmd.step);

    const resident_proof_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "check", "scripts/proof/resident.id" });
    resident_proof_cmd.step.dependOn(b.getInstallStep());
    resident_proof_cmd.setCwd(b.path("."));
    const resident_proof_step = b.step("resident-proof", "CATALOG-ZERO: lib/semantic relation registry must not exist");
    resident_proof_step.dependOn(&resident_proof_cmd.step);

    const semantic_proof_cmd = b.addSystemCommand(&.{
        "./zig-out/bin/idol",
        "check",
        "scripts/proof/vocabulary.id",
        "scripts/proof/audit.id",
        "scripts/proof/semantic.id",
        "scripts/proof/view.id",
        "scripts/proof/fs.id",
        "scripts/proof/core.id",
        "scripts/proof/graph.id",
        "scripts/proof/zerostd.id",
        "scripts/proof/resident.id",
        "gate/graph.id",
    });
    semantic_proof_cmd.step.dependOn(b.getInstallStep());
    semantic_proof_cmd.setCwd(b.path("."));
    const semantic_proof_step = b.step("semantic-proof", "SH-10: proof suite orchestrator and sub-proof routers (static check)");
    semantic_proof_step.dependOn(&semantic_proof_cmd.step);

    const graph_proof_cmd = b.addSystemCommand(&.{
        "./zig-out/bin/idol",
        "check",
        "scripts/canon.id",
        "scripts/proof/graph.id",
        "gate/graph.id",
    });
    graph_proof_cmd.step.dependOn(b.getInstallStep());
    graph_proof_cmd.setCwd(b.path("."));

    const graph_proof_run_cmd = b.addSystemCommand(&.{
        "./zig-out/bin/idol",
        "run",
        "scripts/proof/graph.id",
        "scripts/ledger/semantic.id",
    });
    graph_proof_run_cmd.step.dependOn(b.getInstallStep());
    graph_proof_run_cmd.setCwd(b.path("."));

    const graph_proof_step = b.step("graph-proof", "GAP-124: graph identity / edge closure static proof and migration gate");
    graph_proof_step.dependOn(&graph_proof_cmd.step);
    graph_proof_step.dependOn(&graph_proof_run_cmd.step);

    const closure_proof_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/proof/closure.id" });
    closure_proof_cmd.step.dependOn(b.getInstallStep());
    closure_proof_cmd.setCwd(b.path("."));
    const closure_proof_step = b.step("closure-proof", "SHC + FTCFTW: semantic proof, ftcftw contracts, shc cheap gates at HEAD");
    closure_proof_step.dependOn(&closure_proof_cmd.step);
    closure_proof_step.dependOn(&semantic_proof_cmd.step);

    const direct_link_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/proof/module.id" });
    direct_link_cmd.step.dependOn(b.getInstallStep());
    direct_link_cmd.setCwd(b.path("."));
    const direct_link_step = b.step("direct-module-link", "A direct-backend program must be able to call a req'd Duo module");
    direct_link_step.dependOn(&direct_link_cmd.step);

    const idiom_cmd = b.addSystemCommand(&.{
        "sh", "-c",
        "git diff -U0 --diff-filter=ACM -- '*.id' | ./zig-out/bin/idol run gate/idiom.id || test $? -eq 3",
    });
    idiom_cmd.setCwd(b.path("."));
    const idiom_step = b.step("idiom-gate", "Every .id file must use canonical Duo idioms");
    idiom_step.dependOn(&idiom_cmd.step);

    const bench_proof_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/proof/benchmark.id" });
    bench_proof_cmd.setCwd(b.path("."));
    bench_proof_cmd.step.dependOn(b.getInstallStep());
    const bench_proof_step = b.step("bench-proof-gate", "P0 benchmark 3-profile correctness + proof artifacts");
    bench_proof_step.dependOn(&bench_proof_cmd.step);

    const idiom_gate_cmd = b.addSystemCommand(&.{
        "sh", "-c",
        "git diff -U0 --diff-filter=ACM -- '*.id' | ./zig-out/bin/idol run gate/idiom.id || test $? -eq 3",
    });
    idiom_gate_cmd.setCwd(b.path("."));
    idiom_gate_cmd.step.dependOn(b.getInstallStep());
    idiom_step.dependOn(&idiom_gate_cmd.step);
    const duo_idiom_step = b.step("duo-idiom-gate", "Alias for idiom-gate (bootstrap name — use idiom-gate)");
    duo_idiom_step.dependOn(&idiom_gate_cmd.step);

    const agent_smoke_cmd = b.addSystemCommand(&.{ "./tools/node/dev/idol-lock", "--", "./zig-out/bin/idol", "run", "scripts/agent_smoke.id" });
    agent_smoke_cmd.setCwd(b.path("."));
    agent_smoke_cmd.step.dependOn(b.getInstallStep());
    const agent_smoke_step = b.step("agent-smoke", "Run tier-0 agent-smoke gate (public safety, coordination, stdlib, meta)");
    agent_smoke_step.dependOn(&source_zero_cmd.step);
    agent_smoke_step.dependOn(&public_safety_cmd.step);
    agent_smoke_step.dependOn(&semantic_architecture_cmd.step);
    agent_smoke_step.dependOn(&agent_smoke_cmd.step);
    test_step.dependOn(agent_smoke_step);

    // The compile-time string hash (codegen/sema `calc_lua_hash`) and the
    // runtime one (`calc_hash` in the emitted prelude) are written twice and
    // must agree bit for bit; a divergence splits the intern pool and shows up
    // as a wrong answer, not an error. Long strings hash a SAMPLE, so the two
    // spellings are no longer trivially the same loop. This fixture differences
    // them on both sides of the 32-byte boundary and carries its own controls.
    const hash_agreement_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "examples/hash/agreement.id" });
    hash_agreement_cmd.setCwd(b.path("."));
    hash_agreement_cmd.step.dependOn(b.getInstallStep());
    const hash_agreement_step = b.step("hash-agreement", "Compile-time vs runtime string hash must agree (intern pool)");
    hash_agreement_step.dependOn(&hash_agreement_cmd.step);
    agent_smoke_step.dependOn(&hash_agreement_cmd.step);

    // semantics-gate — two SILENT WRONG ANSWERS, both convicted by value.
    //
    // gap[077]: `a, b = b, a` wrote its targets left to right, so the swap
    // destroyed one of its own operands — `2 2` for a=1,b=2. gap[102]: a body
    // whose final expression was a CALL resolved to the preceding statement
    // instead, so `p = 5` then `d2(p)` RETURNED 5 through the direct backend
    // where C returned 25, and sema type-checked the binding as the return
    // (which is what held this very gate red).
    //
    // Tier 0, and by value rather than by exit status, because both defects
    // produced plausible answers on BOTH backends: a differential cannot
    // convict a wrong answer two backends agree on. Each fixture carries its
    // negative twin and its positive control — the non-overlapping assignment
    // that must keep its shape, the failure pack that must not regress, and
    // the trailing-effect body whose answer really is the preceding binding.
    const semantics_paths = [_][]const u8{
        "examples/demand/swap.id",
        "examples/demand/tail.id",
    };
    const semantics_step = b.step("semantics-gate", "Simultaneous assignment and tail-demand return, by value");
    semantics_step.dependOn(b.getInstallStep());
    inline for (semantics_paths) |path| {
        const cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", path });
        cmd.setCwd(b.path("."));
        cmd.step.dependOn(b.getInstallStep());
        semantics_step.dependOn(&cmd.step);
        agent_smoke_step.dependOn(&cmd.step);
    }

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
    // all. It spawns the servers in a scratch cwd, because `duo run x.id`
    // drops `x.out` beside itself and this gate guards the tree it runs in.
    const mcp_gate_cmd = b.addSystemCommand(&.{ "./tools/node/dev/mcp-gate" });
    mcp_gate_cmd.setCwd(b.path("."));
    mcp_gate_cmd.step.dependOn(b.getInstallStep());
    const mcp_gate_step = b.step("mcp-gate", "MCP servers must handshake, serve their full tool census, and answer by value");
    mcp_gate_step.dependOn(&mcp_gate_cmd.step);
    // Tier 0: a dead MCP server is a dead coordination plane.
    agent_smoke_step.dependOn(&mcp_gate_cmd.step);

    // explain-gate — `duo explain` is the compiler's only projection of live
    // codegen state (optimization outcomes, assumption guards, the transform
    // engine's provenance log and tier-1 registry). Its four `.id` consumers —
    // scripts/explain.id, scripts/contract.id, scripts/transform.id and the
    // now-deleted scripts/cfloor.id — ALL refused to run when measured: the
    // first three were invoked as `idol run --backend=c …` and `--backend=c` is
    // RETIRED (exit 1, by diagnostic), and cfloor.id was outside the direct
    // backend's subset (DNB001 `mod-global-written:rows`). `consumers = 0`,
    // which HPLS §8 makes P0 debt, and the same census is what condemned the
    // `realize`/`semantic` cascade deleted alongside this.
    //
    // Shell, not `.id`, for one measured reason: it is the only gate form that
    // executes today. It asserts BYTES (explain exits 0 on a contract violation
    // by design, so exit status decides nothing) and is positive-controlled.
    // Verified load-bearing by driving it at the pre-change compiler, where row
    // R1 fails on `lower.cequiv` — the realization plan that selected a backend
    // the compiler refuses. Fold it into the `.id` gates when the direct backend
    // grows `mod-global-written` and `unresolved-application-facts`.
    const explain_gate_cmd = b.addSystemCommand(&.{"./tools/node/dev/explain-gate"});
    explain_gate_cmd.setCwd(b.path("."));
    explain_gate_cmd.step.dependOn(b.getInstallStep());
    const explain_gate_step = b.step("explain-gate", "duo explain must project live compiler state, asserted by value");
    explain_gate_step.dependOn(&explain_gate_cmd.step);
    // Tier 0: an unprojected optimizer is an undiagnosable one.
    agent_smoke_step.dependOn(&explain_gate_cmd.step);

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
    const lsp_gate_cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "--backend=c", "tools/lsp/gate.id" });
    lsp_gate_cmd.setCwd(b.path("."));
    lsp_gate_cmd.step.dependOn(b.getInstallStep());
    const lsp_gate_step = b.step("lsp-gate", "The LSP must handshake, survive a document close, and answer by value");
    lsp_gate_step.dependOn(&lsp_gate_cmd.step);
    // Tier 0: an untested language server is an untested front end, and every
    // front end is gated.
    agent_smoke_step.dependOn(&lsp_gate_cmd.step);

    // G-061 tier-0 metaprogramming smokes (combinator dispatch + derive bundles)
    const meta_smoke_paths = [_][]const u8{
        "examples/json/iteration.id",
        "examples/boring/anagram.id",
        "examples/boring/fizzbuzz.id",
        "examples/boring/fib.id",
        "examples/boring/primes.id",
        "examples/boring/sort/quick.id",
        "examples/boring/search/binary.id",
        "examples/boring/mat/mul.id",
        "examples/layout/guard.id",
        "examples/layout/loop/body.id",
        "examples/demand/result.id",
        "examples/demand/swap.id",
        "examples/demand/tail.id",
        "examples/pack/consume.id",
        "examples/projection/descriptor.id",
        "examples/read/stream.id",
        "examples/native/record.id",
        "examples/control/default.id",
    };
    const meta_smoke_step = b.step("meta-smoke", "Run canonical teaching examples under idol run");
    meta_smoke_step.dependOn(b.getInstallStep());
    inline for (meta_smoke_paths) |path| {
        const cmd = b.addSystemCommand(&.{ "./zig-out/bin/idol", "run", "scripts/idol_lock.id", "--", "./zig-out/bin/idol", "run", path });
        cmd.setCwd(b.path("."));
        meta_smoke_step.dependOn(&cmd.step);
    }

    // G-061 strict dispatch gate: metaprogramming smoke under DUO_TRANSFORM_GATE=1
    const meta_gate_cmd = b.addSystemCommand(&.{
        "bash",                                                                                                                                        "-c",
        "DUO_TRANSFORM_GATE=1 DUO_PROVENANCE=1 ./zig-out/bin/idol run scripts/idol_lock.id -- ./zig-out/bin/idol run examples/parity/each.id",
    });
    meta_gate_cmd.setCwd(b.path("."));
    meta_gate_cmd.step.dependOn(b.getInstallStep());
    const meta_gate_step = b.step("meta-gate", "Run tier-0 metaprogramming smoke with DUO_TRANSFORM_GATE=1");
    meta_gate_step.dependOn(&meta_gate_cmd.step);
}
