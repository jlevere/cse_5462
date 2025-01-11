const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const server_exe = b.addExecutable(.{
        .name = "server",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/server.zig"),
    });

    b.installArtifact(server_exe);

    const build_server_step = b.step("server", "Build the server");
    build_server_step.dependOn(&server_exe.step);

    const server_tests = b.addTest(.{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_server_tests = b.addRunArtifact(server_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_server_tests.step);
}
