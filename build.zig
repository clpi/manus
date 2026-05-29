const std = @import("std");

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
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run duo");
    run_step.dependOn(&run_cmd.step);

    const test_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_compile_fail_tests.sh" });
    test_cmd.setCwd(b.path("."));
    test_cmd.step.dependOn(b.getInstallStep());
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_cmd.step);

    const bench_cmd = b.addSystemCommand(&.{ "bash", "scripts/run_benchmark.sh" });
    bench_cmd.setCwd(b.path("."));
    bench_cmd.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run Duo vs C benchmark suite");
    bench_step.dependOn(&bench_cmd.step);
}
