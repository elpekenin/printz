const std = @import("std");

pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // mod
    const mod = b.addModule("printz", .{
        .root_source_file = b.path("src/root.zig"),
        // NOTE: target is needed to .addTest based on this mod
        .target = target,
    });

    // lib, for C users
    _ = b.addLibrary(.{
        .name = "printz",
        .root_module = mod,
    });

    // exe
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
        .link_libc = true, // fwrite used
    });
    exe_mod.addImport("printz", mod);
    const exe = b.addExecutable(.{
        .root_module = exe_mod,
        .name = "printz",
    });
    b.installArtifact(exe);

    // run
    const run_step = b.step("run", "run the CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // TODO: write tests
    const test_suite = b.addTest(.{
        .root_module = mod,
    });
    test_suite.linkLibC();
    const run_tests = b.addRunArtifact(test_suite);
    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_tests.step);
}
