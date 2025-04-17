const std = @import("std");
const clap = @import("clap");
const UDPSocket = @import("sock.zig").UDPSocket;
const file = @import("file_chunking.zig");
const build_info = @import("build_info");
const FileRegistry = @import("file_registry.zig").FileRegistry;
const ChunkInfo = @import("file_registry.zig").ChunkInfo;
const bflib = @import("bloom_filter.zig");

const BloomFilter = bflib.WyBloomFilter;

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

    download_mgr: DownloadManager,

    pub fn init(
        alloc: std.mem.Allocator,
        file_dir: std.fs.Dir,
    ) !Self {
        const sock = try UDPSocket.init(false);
        return .{
            .cache = try file.ChunkDir.init(alloc, file_dir, CACHENAME),
            .socket = sock,
            .epoll = try Epoll.init(),
            .files = try FileRegistry.init(alloc),
            .server_addr = undefined,
            .alloc = alloc,
            .download_mgr = try DownloadManager.init(alloc, sock),
        };
    }

    pub fn deinit(self: *Self) void {
        self.download_mgr.deinit();
        self.socket.deinit();
        self.epoll.deinit();
        self.files.deinit();
    }

    pub fn runEventLoop(self: *Self) !void {
        try self.epoll.addFd(self.socket.socketfd, std.os.linux.EPOLL.IN);
        try self.epoll.addFd(std.io.getStdIn().handle, std.os.linux.EPOLL.IN);

        const timer_fd = try std.posix.timerfd_create(
            @as(std.os.linux.timerfd_clockid_t, @enumFromInt(1)), // CLOCK_MONOTONIC
            std.os.linux.TFD{ .CLOEXEC = true },
        );
        defer std.posix.close(timer_fd);

        var new_value = std.os.linux.itimerspec{
            .it_interval = .{ .sec = 1, .nsec = 0 },
            .it_value = .{ .sec = 1, .nsec = 0 },
        };

        try std.posix.timerfd_settime(
            timer_fd,
            std.os.linux.TFD.TIMER{ .ABSTIME = true },
            &new_value,
            null,
        );

        try self.epoll.addFd(timer_fd, std.os.linux.EPOLL.IN);

        while (true) {
            const num_events = try self.epoll.wait();

            for (0..num_events) |i| {
                const current_fd = self.epoll.events[i].data.fd;

                if (current_fd == self.socket.socketfd) {
                    try self.handleSocketEvent();
                } else if (current_fd == std.io.getStdIn().handle) {
                    try self.handleStdinEvent();
                } else if (current_fd == timer_fd) {
                    try self.handleTimerEvent();
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

        // First check if the packet matches any active download
        if (try self.download_mgr.handleIncomingChunkData(buf[0..recv_info.bytes_recv], recv_info.sender, &self.cache)) {
            return; // Packet was for an active download
        }

        // If not an active download packet, try to parse as JSON command
        try self.handleJsonCommand(buf[0..recv_info.bytes_recv], recv_info.sender);
    }

    fn handleJsonCommand(self: *Self, data: []const u8, sender: std.net.Address) !void {
        var json_values = std.json.parseFromSlice(
            std.json.Value,
            self.alloc,
            data,
            .{ .allocate = .alloc_always },
        ) catch |parse_err| {
            log.err("Unable to parse JSON: {any}\nMessage: {s}", .{
                parse_err,
                data,
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
                log.info("Got upload message from {}", .{sender});
            },
            .query => {
                log.info("Got query message from {}", .{sender});
            },
            .queryResponse => {
                try self.processQueryResponse(&json_values.value);
            },
            .getChunk => {
                try self.handleGetChunkRequest(&json_values.value, sender);
            },
            .notfound => {
                log.warn("Unknown command: {s} from {}", .{ data, sender });
            },
        }
    }

    fn handleTimerEvent(self: *Self) !void {
        try self.download_mgr.checkTimeouts();
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

                    try self.getFile(hash);
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

    fn handleGetChunkRequest(self: *Self, json_value: *std.json.Value, sender: std.net.Address) !void {
        const chunk_name = json_value.object.get("chunkName") orelse {
            log.warn("getChunk missing chunkName field from {}", .{sender});
            return;
        };

        const chunk_data = self.cache.fetchChunk(chunk_name.string, self.alloc) catch |err| {
            log.warn("Failed to fetch chunk {s}: {s}", .{ chunk_name.string, @errorName(err) });
            return;
        };
        defer self.alloc.free(chunk_data);

        const max_chunk_size = 1472; // fit inside an 1500 mtu window with some overhead of the pkt header

        var chunks = std.mem.window(u8, chunk_data, max_chunk_size, max_chunk_size);
        while (chunks.next()) |chunk| {
            log.debug("Sending fragment {s}", .{chunk_name.string});
            try self.socket.sendTo(sender, chunk);
        }

        log.info("Sent chunk {s} ({d} bytes) to {}", .{ chunk_name.string, chunk_data.len, sender });
    }

    fn getFile(self: *Self, filehash: []const u8) !void {
        // Check if file already exists locally
        const maybe_filename = try self.files.getFileName(filehash, self.alloc);
        defer if (maybe_filename) |filename| self.alloc.free(filename);

        if (maybe_filename == null) {
            log.err("No filename known for file hash {s}", .{filehash});
            return;
        }

        const file_stat = self.cache.dir.statFile(maybe_filename.?) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (file_stat != null and file_stat.?.kind == .file) {
            log.info("File {s} already exists at {s}", .{ filehash, maybe_filename.? });
            return;
        }

        // Check if already being downloaded
        if (self.download_mgr.pending_chunks.items.len != 0) {
            log.err("There is already a file downloading, wait until it is done", .{});
            return;
        }

        // Get file information from registry
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const thisfile = try self.files.getFile(filehash, arena_allocator);

        try self.cache.writeManifest(thisfile);

        // Start download through download manager
        try self.download_mgr.getFile(thisfile, &self.cache);

        log.info("Started download for {s}", .{maybe_filename.?});
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

                    var maybe_chunks = try self.alloc.alloc(ChunkInfo, hashes.items.len);
                    defer self.alloc.free(maybe_chunks);

                    if (size < 0) continue;

                    for (clients.items) |client| {
                        const client_ip = (client.object.get("IP") orelse continue).string;
                        const clent_port = (client.object.get("Port") orelse continue).integer;

                        const port = @as(u16, @intCast(clent_port));
                        const client_addr = try std.net.Address.parseIp(client_ip, port);

                        for (hashes.items, 0..) |chunk, i| {
                            maybe_chunks[i] = .{
                                .chunkName = chunk.object.get("chunkName").?.string,
                                .chunkSize = chunk.object.get("chunkSize").?.integer,
                            };
                        }

                        self.files.registerFile(
                            filename,
                            @intCast(size),
                            hash,
                            client_addr,
                            maybe_chunks,
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

const DownloadManager = struct {
    const Self = @This();
    const ChunkRequest = struct {
        hash: []const u8,
        size: usize,
        buff: std.ArrayList(u8),
        peer: std.net.Address,
    };

    current_request: ?ChunkRequest, // The chunk we're currently downloading
    pending_chunks: std.ArrayList(ChunkInfo), // Chunks waiting to be downloaded
    available_peers: std.ArrayList(std.net.Address), // Available peers to download from
    fileHash: []const u8,
    alloc: std.mem.Allocator,
    sock: UDPSocket,
    timeout: i64,

    pub fn init(alloc: std.mem.Allocator, sock: UDPSocket) !Self {
        return .{
            .alloc = alloc,
            .sock = sock,
            .timeout = 0,
            .current_request = null,
            .fileHash = undefined,
            .pending_chunks = std.ArrayList(ChunkInfo).init(alloc),
            .available_peers = std.ArrayList(std.net.Address).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.current_request) |*request| {
            self.alloc.free(request.hash);
            request.buff.deinit();
        }
        for (self.pending_chunks.items) |chunk| {
            self.alloc.free(chunk.chunkName);
        }
        self.pending_chunks.deinit();
        self.available_peers.deinit();

        if (self.fileHash.len != 0) {
            self.alloc.free(self.fileHash);
        }
    }

    pub fn getFile(self: *Self, thisfile: FileRegistry.FileData, cache: *file.ChunkDir) !void {
        // Clear current state
        if (self.current_request) |*request| {
            self.alloc.free(request.hash);
            request.buff.deinit();
            self.current_request = null;
        }

        // Copy chunks and peers
        self.pending_chunks.clearRetainingCapacity();
        self.available_peers.clearRetainingCapacity();

        for (thisfile.chunk_hashes.items) |chunk| {
            try self.pending_chunks.append(.{
                .chunkName = try self.alloc.dupe(u8, chunk.chunkName),
                .chunkSize = chunk.chunkSize,
            });
        }

        for (thisfile.clientIPs.items) |peer| {
            try self.available_peers.append(peer);
        }

        self.fileHash = try self.alloc.dupe(u8, thisfile.fullFileHash);

        // Start downloading
        try self.startNextChunk(cache);
    }

    fn startNextChunk(self: *Self, cache: *file.ChunkDir) !void {
        // Make sure we have chunks and peers
        if (self.pending_chunks.items.len == 0) {
            log.info("All chunks downloaded successfully", .{});
            if (try cache.reassembleFile(self.fileHash)) {
                log.info("File {s} sucessfully reassembled!", .{self.fileHash});
            }
            return;
        }

        if (self.available_peers.items.len == 0) {
            log.err("No peers available to download from", .{});
            return;
        }

        // Get the next chunk and the first peer
        const chunk = self.pending_chunks.items[0];
        const peer = self.available_peers.items[0];

        // Create the request
        self.current_request = .{
            .hash = try self.alloc.dupe(u8, chunk.chunkName),
            .size = @as(usize, @intCast(chunk.chunkSize)),
            .buff = std.ArrayList(u8).init(self.alloc),
            .peer = peer,
        };

        std.debug.print("Created new request\n", .{});

        // Send the request
        try self.sendGetChunk();

        std.debug.print("Send get chunk request from startNextChunk\n", .{});
    }

    fn sendGetChunk(self: *Self) !void {
        if (self.current_request) |request| {
            var json_request = std.ArrayList(u8).init(self.alloc);
            defer json_request.deinit();

            try std.json.stringify(.{
                .requestType = "getChunk",
                .chunkName = request.hash,
            }, .{}, json_request.writer());

            self.timeout = std.time.timestamp() + 10; // 10sec timeout
            try self.sock.sendTo(request.peer, json_request.items);
            log.info("Requested chunk {s} from {}", .{ request.hash, request.peer });
        }
    }

    // handles incoming data. Returns true if its a chunk
    pub fn handleIncomingChunkData(self: *Self, data: []const u8, peer: std.net.Address, cache: *file.ChunkDir) !bool {
        // Check if we have an active request
        const request = if (self.current_request) |*req| req else return false;

        // Only accept data from the peer we requested from
        if (!std.net.Address.eql(peer, request.peer)) {
            return false;
        }

        // Add the data to our buffer
        try request.buff.appendSlice(data);

        // Check if chunk is complete
        if (request.buff.items.len >= request.size) {
            var buf: [64]u8 = undefined;
            const hash = try sha256(request.buff.items, &buf);

            if (!std.mem.eql(u8, request.hash, hash)) {
                log.warn("Invalid chunk hash received", .{});
                // Retry with the next peer
                try self.switchPeer();
                return true;
            }

            // Valid chunk received, save it
            try cache.saveChunk(request.hash, request.buff.items);

            log.info("Finished save chunk", .{});

            // Clean up this request
            self.alloc.free(request.hash);
            request.buff.deinit();

            log.info("Freed request hash and buffer", .{});

            // Remove the first chunk from pending
            _ = self.pending_chunks.orderedRemove(0);

            log.info("Removed the first chunk from pending", .{});

            // Clear current request
            self.current_request = null;

            // Start next chunk
            try self.startNextChunk(cache);

            log.info("Start next chunk", .{});

            return true;
        } else {
            log.info("{d} bytes remaining", .{self.current_request.?.size - self.current_request.?.buff.items.len});
        }

        return true;
    }

    // Switch to the next available peer
    fn switchPeer(self: *Self) !void {
        if (self.available_peers.items.len <= 1) {
            log.err("No alternative peers available", .{});

            if (self.current_request) |req| {
                self.alloc.free(req.hash);
                req.buff.deinit();

                // Clear current request since we cant complete it
                self.current_request = null;
                self.pending_chunks.clearRetainingCapacity();
            }
            return;
        }

        // Remove the first peer
        _ = self.available_peers.orderedRemove(0);
        log.info("Switching to next peer: {}", .{self.available_peers.items[0]});

        // Update the current request with the new peer
        if (self.current_request) |*request| {
            request.peer = self.available_peers.items[0];
            request.buff.clearRetainingCapacity();
            try self.sendGetChunk();
        }
    }

    // Check for timeouts
    pub fn checkTimeouts(self: *Self) !void {
        if (self.current_request) |_| {
            const now = std.time.timestamp();
            if (self.current_request != null and self.timeout <= now) {
                log.warn("Request timed out", .{});
                try self.switchPeer();
            }
        }
    }
};

fn hashAddress(addr: std.net.Address) u64 {
    var hasher = std.hash.Wyhash.init(0);

    switch (addr.any.family) {
        std.os.AF_INET => {
            const ip = addr.in;
            hasher.update(std.mem.asBytes(&ip.sa.addr));
            hasher.update(std.mem.asBytes(&ip.sa.port));
        },
        std.os.AF_INET6 => {
            const ip = addr.in6;
            hasher.update(&ip.sa.addr);
            hasher.update(std.mem.asBytes(&ip.sa.port));
        },
        else => unreachable,
    }

    return hasher.final();
}

/// Hash data using SHA-256 and write the lowercase hexadecimal result into buf.
pub fn sha256(data: []const u8, buf: []u8) ![]u8 {
    var sha = std.crypto.hash.sha2.Sha256.init(.{});
    sha.update(data);
    const hash = sha.finalResult();

    return try std.fmt.bufPrint(
        buf,
        "{s}",
        .{std.fmt.fmtSliceHexLower(&hash)},
    );
}
