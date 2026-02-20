const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dev profile: game in Debug, deps/framework in ReleaseFast.
    // Use plain `zig build` for dev, `zig build -Doptimize=ReleaseFast` for full release.
    const dev = optimize == .Debug;
    const dep_optimize: std.builtin.OptimizeMode = if (dev) .ReleaseFast else optimize;

    const sdl3_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = dep_optimize,
    });

    const orb_mod = b.createModule(.{
        .root_source_file = b.path("src/orb/orb.zig"),
        .target = target,
        .optimize = dep_optimize,
    });
    orb_mod.linkLibrary(sdl3_dep.artifact("SDL3"));

    const options = b.addOptions();
    options.addOption(bool, "dev", dev);

    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/averain/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_mod.addImport("orb", orb_mod);
    game_mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "averain",
        .root_module = game_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run averain");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/orb/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
