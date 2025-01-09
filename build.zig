const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const client_exe = b.addExecutable(.{
        .name = "client",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/client.zig"),
    });

    b.installArtifact(client_exe);

    const server_exe = b.addExecutable(.{
        .name = "server",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/server.zig"),
    });

    b.installArtifact(server_exe);

    const run_client = b.addRunArtifact(client_exe);
    const run_server = b.addRunArtifact(server_exe);

    run_client.step.dependOn(b.getInstallStep());
    run_server.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_client.addArgs(args);
        run_server.addArgs(args);
    }

    const run_client_step = b.step("client", "Run the client application");
    run_client_step.dependOn(&run_client.step);

    const run_server_step = b.step("server", "Run the server application");
    run_server_step.dependOn(&run_server.step);

    // Add tests for both executables
    const client_tests = b.addTest(.{
        .root_source_file = b.path("client.zig"),
        .target = target,
        .optimize = optimize,
    });

    const server_tests = b.addTest(.{
        .root_source_file = b.path("server.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_client_tests = b.addRunArtifact(client_tests);
    const run_server_tests = b.addRunArtifact(server_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_client_tests.step);
    test_step.dependOn(&run_server_tests.step);
}
