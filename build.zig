const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // maybepile library source module
    const maybepile_module = b.createModule(.{
        .root_source_file = b.path("src/maybepile.zig"),
        .target = target,
        .optimize = optimize,
    });

    // maybepile static library
    const libmaybepile = b.addLibrary(.{
        .name = "maybepile",
        .linkage = .static,
        .root_module = maybepile_module
    });

    b.installArtifact(libmaybepile);

    // maybepile testing
    const unit_tests = b.addTest(.{ .root_module = maybepile_module });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const install_unit_tests = b.addInstallArtifact(unit_tests, .{});

    const install_tests_step = b.step("install-tests", "Install unit tests");
    install_tests_step.dependOn(&install_unit_tests.step);
    

}
