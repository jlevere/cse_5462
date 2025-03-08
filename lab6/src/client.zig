const std = @import("std");
const clap = @import("clap");
const UDPSocket = @import("sock.zig").UDPSocket;
const file = @import("file_chunking.zig");
const build_info = @import("build_info");
const FileRegistry = @import("file_registry.zig").FileRegistry;

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

    var client = try Client.init(gpa, dir);
    defer client.deinit();

    // Clear cache if requested
    if (res.args.clear != 0) {
        try client.clearCache();
    }

    // Rebuild cache if requested or if it doesn't exist
    if (res.args.rebuild != 0 or !try client.cache.cacheExists()) {
        try client.rebuildCache();
    }

    // If IP/port are provided, send the data
    if (res.args.ip != null and res.args.port != null) {
        try client.uploadLocalFiles(try std.net.Address.parseIp(res.args.ip.?, res.args.port.?));
    } else {
        std.log.err("Both IP and port are required for sending\n", .{});
        return;
    }

    // data has been uploaded at this point, now we need to wait for updates from the server

}

const Client = struct {
    const Self = @This();

    const CACHENAME = "CHUNKS";

    cache: file.ChunkDir,
    socket: UDPSocket,

    alloc: std.mem.Allocator,

    pub fn init(
        alloc: std.mem.Allocator,
        file_dir: std.fs.Dir,
    ) !Self {
        return .{
            .cache = try file.ChunkDir.init(alloc, file_dir, CACHENAME),
            .socket = try UDPSocket.init(true),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        self.socket.deinit();
    }

    pub fn rebuildCache(self: *Self) !void {
        try self.clearCache();
        try self.cache.buildCache();
    }

    pub fn clearCache(self: *Self) !void {
        if (try self.cache.cacheExists()) {
            try self.cache.clearCache();
        }
    }

    pub fn uploadLocalFiles(self: *Self, addr: std.net.Address) !void {
        errdefer |err| std.log.err("Uploading local files failed with err {}\n", err);

        var dir = try self.cache.dir.openDir(
            CACHENAME,
            .{ .iterate = true },
        );
        defer dir.close();

        var iter = file.ChunkDir.Iterator.init(self.alloc, dir);
        defer iter.deinit();

        var buf = std.ArrayList(u8).init(self.alloc);
        defer buf.deinit();
        const writer = buf.writer();

        try writer.writeAll("{\"requestType\":\"upload\",\"files\":[");
        while (try iter.next()) |entry| {
            try entry.serialize(writer);
            try writer.writeAll(",");
        }
        try writer.writeAll("]}");

        try self.socket.sendTo(addr, buf.items);
    }
};
