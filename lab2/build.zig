const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = b.option([]const u8, "version", "Set binary version") orelse "HEAD";

    const build_info = b.addOptions();
    build_info.addOption([]const u8, "version", version);

    const clap = b.dependency("clap", .{});

    const server_exe = b.addExecutable(.{
        .name = "server",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/server.zig"),
    });

    server_exe.root_module.addImport("clap", clap.module("clap"));
    server_exe.root_module.addOptions("build_info", build_info);

    b.installArtifact(server_exe);

    const client_exe = b.addExecutable(.{
        .name = "client",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/client.zig"),
    });

    client_exe.root_module.addImport("clap", clap.module("clap"));
    client_exe.root_module.addOptions("build_info", build_info);

    b.installArtifact(client_exe);

    const build_server_step = b.step("server", "Build the server");
    build_server_step.dependOn(&server_exe.step);

    const build_client_step = b.step("client", "Build the client");
    build_client_step.dependOn(&client_exe.step);

    const server_tests = b.addTest(.{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_server_tests = b.addRunArtifact(server_tests);

    const client_tests = b.addTest(.{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_client_tests = b.addRunArtifact(client_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_server_tests.step);
    test_step.dependOn(&run_client_tests.step);
}
