const std = @import("std");
const clap = @import("clap");
const UDPSocket = @import("sock.zig").UDPSocket;
const file = @import("file_chunking.zig");
const build_info = @import("build_info");

const json = std.json;

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa_impl.deinit() == .leak) {
        std.log.warn("gpa has leaked\n", .{});
    };
    const gpa = gpa_impl.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help       Display this help and exit.
        \\--version        Display the current version
        \\--ip <str>       IP address to send to (optional)
        \\--port <u16>     Port number to send to (optional)
        \\--dir <str>     Path to input directory (optional)
        \\<str>...     Positional arguments [IP] [PORT] [DIR]
        \\
    );

    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return;
    };
    defer res.deinit();

    if (res.args.version != 0) {
        std.debug.print("{s}\n", .{build_info.version});
        return;
    }

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    const ip = res.args.ip orelse blk: {
        if (res.positionals[0].len < 1) {
            std.log.err("IP address required", .{});
            std.log.err("Use --ip or provide as first argument", .{});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        }
        break :blk res.positionals[0][0];
    };

    const port = res.args.port orelse blk: {
        if (res.positionals[0].len < 2) {
            std.log.err("Port number required", .{});
            std.log.err("Use --port or provide as second argument", .{});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        }
        const port_str = res.positionals[0][1];
        break :blk std.fmt.parseInt(u16, port_str, 10) catch |err| {
            std.log.err("Invalid port '{s}': {s}", .{ port_str, @errorName(err) });
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        };
    };

    const dir_path = res.args.dir orelse blk: {
        if (res.positionals[0].len < 3) {
            std.log.err("Dir path required", .{});
            std.log.err("Use --file or provide as third argument", .{});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        }
        break :blk res.positionals[0][2];
    };

    var dir = std.fs.cwd().openDir(
        dir_path,
        .{
            .iterate = true,
        },
    ) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err("Dir not found: '{s}'", .{dir_path});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        },
        error.AccessDenied => {
            std.log.err("Access denied to dir: '{s}'", .{dir_path});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        },
        else => {
            std.log.err("Unexpected error accessing '{s}': {s}", .{ dir_path, @errorName(err) });
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        },
    };
    defer dir.close();

    const cache_name = "CHUNKS";

    var chunk_dir = try file.ChunkDir.init(gpa, dir, cache_name);
    defer chunk_dir.deinit();

    chunk_dir.createCacheDir() catch |err| switch (err) {
        error.CacheDirAlreadyExists => {
            std.log.err("Cache directory already exists", .{});
            return;
        },
        else => {
            const cache_path = try dir.realpathAlloc(gpa, ".");
            defer gpa.free(cache_path);

            std.log.err("Unexpected error creating cache at path '{s}/{s}': {s}", .{ cache_path, cache_name, @errorName(err) });
        },
    };

    try chunk_dir.buildCache();

    var socket = try UDPSocket.init();
    defer socket.deinit();

    var cache_dir = try dir.openDir(cache_name, .{ .iterate = true });
    defer cache_dir.close();

    var iter = file.File.Iterator.init(gpa, cache_dir);
    defer iter.deinit();

    var buf = std.ArrayList(u8).init(gpa);
    defer buf.deinit();

    const writer = buf.writer();

    while (try iter.next()) |entry| {
        try entry.serialize(writer);

        try socket.sendTo(try std.net.Address.resolveIp(ip, port), buf.items);

        buf.clearRetainingCapacity();
    }
}
