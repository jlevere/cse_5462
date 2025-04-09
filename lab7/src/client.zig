const std = @import("std");
const clap = @import("clap");
const UDPSocket = @import("sock.zig").UDPSocket;
const file = @import("file_chunking.zig");
const build_info = @import("build_info");
const FileRegistry = @import("file_registry.zig").FileRegistry;

const json = std.json;

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const log = std.log.scoped(.client);

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
        return;
    }

    // Rebuild cache if requested or if it doesn't exist
    if (res.args.rebuild != 0 or !try client.cache.cacheExists()) {
        try client.rebuildCache();
    }

    // not a network command
    if (res.args.ip == null and res.args.port == null) {
        return;
    }

    if (res.args.ip == null or res.args.port == null) {
        std.log.err("Both IP and port are required for sending\n", .{});
        return;
    }

    // Buisness logic

    try client.socket.bind(try std.net.Address.parseIp(res.args.ip.?, 0));
    try client.setServer(try std.net.Address.parseIp(res.args.ip.?, res.args.port.?));

    try client.uploadLocalFiles();

    try client.runEventLoop();
}

const Client = struct {
    const Self = @This();

    const CACHENAME = "CHUNKS";

    cache: file.ChunkDir,
    socket: UDPSocket,

    server_addr: std.net.Address,
    epoll: Epoll,

    files: FileRegistry,

    alloc: std.mem.Allocator,

    pub fn init(
        alloc: std.mem.Allocator,
        file_dir: std.fs.Dir,
    ) !Self {
        return .{
            .cache = try file.ChunkDir.init(alloc, file_dir, CACHENAME),
            .socket = try UDPSocket.init(false),
            .epoll = try Epoll.init(),
            .files = try FileRegistry.init(alloc),
            .server_addr = undefined,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        self.socket.deinit();
        self.epoll.deinit();
        self.files.deinit();
    }

    pub fn runEventLoop(self: *Self) !void {
        try self.epoll.addFd(self.socket.socketfd, std.os.linux.EPOLL.IN);
        try self.epoll.addFd(std.io.getStdIn().handle, std.os.linux.EPOLL.IN);

        while (true) {
            const num_events = try self.epoll.wait();

            for (0..num_events) |i| {
                const current_fd = self.epoll.events[i].data.fd;

                if (current_fd == self.socket.socketfd) {
                    try self.handleSocketEvent();
                } else if (current_fd == std.io.getStdIn().handle) {
                    try self.handleStdinEvent();
                }
            }
        }
    }

    pub fn handleSocketEvent(self: *Self) !void {
        var buf = try self.alloc.alloc(u8, 65535);
        defer self.alloc.free(buf);

        const recv_info = self.socket.recvFrom(buf) catch |err| {
            switch (err) {
                error.WouldBlock => return,
                else => return err,
            }
        };

        var json_values = std.json.parseFromSlice(
            std.json.Value,
            self.alloc,
            buf[0..recv_info.bytes_recv],
            .{ .allocate = .alloc_always },
        ) catch |parse_err| {
            log.err("Unable to parse JSON: {any}\nMessage: {s}", .{
                parse_err,
                buf[0..recv_info.bytes_recv],
            });
            return;
        };
        defer json_values.deinit();

        const Commands = enum { upload, query, queryResponse, getChunk, notfound };
        const request_type = (json_values.value.object.get("requestType") orelse
            std.json.Value{ .string = "notfound" }).string;
        const case = std.meta.stringToEnum(Commands, request_type) orelse Commands.notfound;

        switch (case) {
            .upload => {
                std.debug.print("got upload msg from {}\n", .{recv_info.sender});
            },
            .query => {
                std.debug.print("got query msg from {}\n", .{recv_info.sender});
            },
            .queryResponse => {
                try self.processQueryResponse(&json_values.value);
            },
            .getChunk => {},
            .notfound => {
                std.debug.print("cmd not found, got {s} from {}\n", .{ buf[0..recv_info.bytes_recv], recv_info.sender });
            },
        }
    }

    pub fn handleStdinEvent(self: *Self) !void {
        var stdin_buffer: [1024]u8 = undefined;
        const stdin = std.io.getStdIn().reader();

        const line = (try stdin.readUntilDelimiterOrEof(&stdin_buffer, '\n')) orelse return;
        const trimmed_line = std.mem.trim(u8, line, " \t\r\n");
        var command_iter = std.mem.splitScalar(u8, trimmed_line, ' ');
        const command_str = command_iter.first();

        const Commands = enum { ls, query, get, help, notfound };

        const case = std.meta.stringToEnum(Commands, command_str) orelse Commands.notfound;
        switch (case) {
            .help => {
                inline for (@typeInfo(Commands).@"enum".fields) |field| {
                    try std.io.getStdOut().writer().print("{s}, ", .{field.name});
                    try std.io.getStdOut().writer().print("\n", .{});
                }
            },
            .ls => {
                try self.displayFiles();
            },
            .query => {
                try self.requestRemoteRegistry();
            },
            .get => {
                if (command_iter.next()) |val| {
                    const idx = std.fmt.parseInt(usize, val, 10) catch {
                        try std.io.getStdOut().writer().print("Specify which file you want by number\n", .{});
                        return;
                    };

                    const hash = try self.files.getHashIdx(idx, self.alloc) orelse {
                        try std.io.getStdOut().writer().print("idx out of range\n", .{});
                        return;
                    };
                    defer self.alloc.free(hash);

                    std.debug.print("asked for hash: {s}\n", .{hash});
                } else {
                    try std.io.getStdOut().writer().print("Specify which file you want by number\n", .{});
                }
            },
            .notfound => {
                if (trimmed_line.len == 0) return;
                std.debug.print("notfound\n", .{});
            },
        }
    }

    fn processQueryResponse(self: *Self, root: *std.json.Value) !void {
        const files = root.object.get("files") orelse {
            log.warn("queryResponse missing files array", .{});
            return;
        };

        switch (files) {
            .array => |items| {
                for (items.items) |item| {
                    const thisfile = item.object;

                    const filename = (thisfile.get("filename") orelse continue).string;
                    const size = (thisfile.get("fileSize") orelse continue).integer;
                    const hash = (thisfile.get("fullFileHash") orelse continue).string;
                    const clients = (thisfile.get("IPInfo") orelse continue).array;
                    const hashes = (thisfile.get("chunk_hashes") orelse continue).array;

                    var chunks = try self.alloc.alloc(FileRegistry.ChunkInfo, hashes.items.len);
                    defer self.alloc.free(chunks);

                    if (size < 0) continue;

                    for (clients.items) |client| {
                        const client_ip = (client.object.get("IP") orelse continue).string;
                        const clent_port = (client.object.get("Port") orelse continue).string;

                        const port = try std.fmt.parseInt(u16, clent_port, 10);
                        const client_addr = try std.net.Address.parseIp(client_ip, port);

                        for (hashes.items, 0..) |chunk, i| {
                            chunks[i] = .{
                                .chunkName = chunk.object.get("chunkName").?.string,
                                .chunkSize = chunk.object.get("chunkSize").?.integer,
                            };
                        }

                        self.files.registerFile(
                            filename,
                            @intCast(size),
                            hash,
                            client_addr,
                            chunks,
                        ) catch |err| {
                            log.warn("Failed to register {s}: {s}", .{ filename, @errorName(err) });
                        };
                    }
                }
            },
            else => {
                log.warn("queryResponse contains non-array files field", .{});
                return;
            },
        }
    }

    pub fn displayFiles(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\n\x1B[2J\x1B[H", .{}); // Clear screen
        try self.files.printSimpleTable(stdout);
    }

    pub fn rebuildCache(self: *Self) !void {
        try self.clearCache();
        try self.cache.createCacheDir();
        try self.cache.buildCache();
    }

    pub fn clearCache(self: *Self) !void {
        if (try self.cache.cacheExists()) {
            try self.cache.clearCache();
        }
    }

    pub fn requestRemoteRegistry(self: *Self) !void {
        try self.socket.sendTo(self.server_addr, "{\"requestType\": \"query\"}");
    }

    pub fn setServer(self: *Self, addr: std.net.Address) !void {
        self.server_addr = addr;
    }

    pub fn uploadLocalFiles(self: *Self) !void {
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

        var extra_fields = std.StringHashMap([]const u8).init(self.alloc);
        defer extra_fields.deinit();
        try extra_fields.put("requestType", "upload");

        while (try iter.next()) |entry| {
            try entry.serialize(writer, extra_fields);
            try self.socket.sendTo(self.server_addr, buf.items);
            buf.clearRetainingCapacity();
        }
    }
};

pub const Epoll = struct {
    fd: i32,
    events: [128]std.os.linux.epoll_event,

    pub fn init() !Epoll {
        const epfd = try std.posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC);
        return .{
            .fd = epfd,
            .events = undefined,
        };
    }

    pub fn deinit(self: *Epoll) void {
        std.posix.close(self.fd);
    }

    pub fn addFd(self: *Epoll, fd: i32, events: u32) !void {
        var ev = std.os.linux.epoll_event{
            .events = events,
            .data = .{ .fd = fd },
        };
        try std.posix.epoll_ctl(self.fd, std.os.linux.EPOLL.CTL_ADD, fd, &ev);
    }

    pub fn wait(self: *Epoll) !usize {
        return std.posix.epoll_wait(self.fd, &self.events, -1);
    }
};
