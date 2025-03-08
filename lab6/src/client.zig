const std = @import("std");
const clap = @import("clap");
const UDPSocket = @import("sock.zig").UDPSocket;
const file = @import("file_chunking.zig");
const build_info = @import("build_info");

const json = std.json;

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa_impl.deinit() == .leak) {
        std.log.warn("gpa has leaked\n", .{});
    };
    const gpa = gpa_impl.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                Display this help and exit
        \\--version                 Display the current version
        \\-d, --dir <str>          Path to input directory (required)
        \\-i, --ip <str>           IP address to send to
        \\-p, --port <u16>         Port number to send to
        \\-r, --rebuild            Rebuild the cache
        \\-c, --clear              Clear the cache
        \\--count                  Count files in cache
        \\<str>...                 Positional arguments [DIR]
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

    if (res.args.help != 0) return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    if (res.args.version != 0) {
        std.debug.print("{s}\n", .{build_info.version});
        return;
    }

    // --dir  required by everything else
    const dir_path = res.args.dir orelse blk: {
        if (res.positionals[0].len < 1) {
            std.log.err("Directory path is required\n", .{});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        }
        break :blk res.positionals[0][0];
    };

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => std.log.err("Directory not found: '{s}'\n", .{dir_path}),
            error.AccessDenied => std.log.err("Access denied to directory: '{s}'\n", .{dir_path}),
            else => std.log.err("Error accessing '{s}': {s}\n", .{ dir_path, @errorName(err) }),
        }
        return err;
    };
    defer dir.close();

    const cache_name = "CHUNKS";
    var chunk_dir = try file.ChunkDir.init(gpa, dir, cache_name);

    // Types of operations requested
    const should_clear = res.args.clear != 0;
    const should_rebuild = res.args.rebuild != 0;
    const has_ip = res.args.ip != null;
    const has_port = res.args.port != null;

    // Clear cache if requested
    if (should_clear) {
        if (!try chunk_dir.cacheExists()) return;
        try chunk_dir.clearCache();
        if (!should_rebuild and !has_ip) return; // Exit if only clearing was requested
    }

    // Rebuild cache if requested or if it doesn't exist
    if (should_rebuild or !try chunk_dir.cacheExists()) {
        if (try chunk_dir.cacheExists()) {
            try chunk_dir.clearCache();
        }

        try chunk_dir.createCacheDir();
        try chunk_dir.buildCache();
        if (!has_ip) return; // Exit if only rebuilding was requested
    }

    // If IP/port are provided, send the data
    if (has_ip and has_port) {
        const ip = res.args.ip.?;
        const port = res.args.port.?;

        var socket = try UDPSocket.init(true);
        defer socket.deinit();

        var cache_dir = try dir.openDir(cache_name, .{ .iterate = true });
        defer cache_dir.close();

        var iter = file.ChunkDir.Iterator.init(gpa, cache_dir);
        defer iter.deinit();

        var buf = std.ArrayList(u8).init(gpa);
        defer buf.deinit();
        const writer = buf.writer();

        while (try iter.next()) |entry| {
            try entry.serialize(writer);
            try socket.sendTo(try std.net.Address.resolveIp(ip, port), buf.items);
            buf.clearRetainingCapacity();
        }
    } else if (has_ip or has_port) {
        std.log.err("Both IP and port are required for sending\n", .{});
        return;
    }
}
