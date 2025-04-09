const std = @import("std");
const bflib = @import("bloom_filter.zig");
const BloomFilter = bflib.BloomFilter;

const wyhash = bflib.wyhash;

const log = std.log.scoped(.FileRegistry);

pub const FileRegistry = struct {
    const Self = @This();

    const expected_items = 100;
    const false_pos_rate = 0.01;

    const n_bits = std.math.ceilPowerOfTwo(
        usize,
        @as(
            usize,
            @intFromFloat(-(@as(f64, @floatFromInt(expected_items)) * @log(false_pos_rate) / (std.math.ln2 * std.math.ln2))),
        ),
    ) catch unreachable;

    const K = @max(
        1,
        @as(
            usize,
            @intFromFloat((@as(f64, @floatFromInt(n_bits)) / expected_items) * std.math.ln2),
        ),
    );

    pub const ChunkInfo = struct {
        chunkName: []const u8,
        chunkSize: i64,
    };

    pub const FileData = struct {
        filename: []const u8,
        fullFileHash: []const u8,
        fileSize: i64,
        clientIPs: std.ArrayList(std.net.Address),
        chunk_hashes: std.ArrayList(ChunkInfo),
    };

    // Store the actual files in multiarraylist
    files: std.MultiArrayList(FileData),

    // Bloomfilter for negitive lookups
    filter: BloomFilter(n_bits, K, wyhash),
    // hashmap for hashloopups (hash -> index in MultiArrayList)
    map: std.StringHashMap(usize),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{
            .files = std.MultiArrayList(FileData){},
            .filter = BloomFilter(n_bits, K, wyhash){},
            .map = std.StringHashMap(usize).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        const slice = self.files.slice();

        for (slice.items(.filename), slice.items(.fullFileHash), slice.items(.clientIPs), slice.items(.chunk_hashes)) |filename, hash, *client_list, *chunk_list| {
            self.alloc.free(filename);
            self.alloc.free(hash);
            client_list.deinit();

            for (chunk_list.items) |chunk| {
                self.alloc.free(chunk.chunkName);
            }
            chunk_list.deinit();
        }
        self.files.deinit(self.alloc);
        self.map.deinit();
    }

    /// Register a new client
    pub fn registerClient() void {}

    /// Regster a new file
    pub fn registerFile(
        self: *Self,
        filename: []const u8,
        fileSize: i64,
        hash: []const u8,
        client_addr: std.net.Address,
        chunk_hashes: ?[]const ChunkInfo,
    ) !void {
        log.debug("register file: {s}:{}:{s}", .{ filename, client_addr, hash });

        // If the file already exists
        if (self.filter.contains(hash)) {
            if (self.map.get(hash)) |file_index| {
                log.debug("reg seen {s}", .{hash});
                var client_list = &self.files.slice().items(.clientIPs)[file_index];

                for (client_list.items) |addr| {
                    if (std.mem.eql(u8, &addr.any.data, &client_addr.any.data)) {
                        return; // Client already registered to this file
                    }
                }

                // add the new client to file
                try client_list.append(client_addr);
                log.debug("added new client {} for {s}", .{ client_addr, hash });
                return;
            }
        }

        // If the file doesnt exist
        const my_hash = try self.alloc.dupe(u8, hash);
        var client_array = try std.ArrayList(std.net.Address).initCapacity(
            self.alloc,
            4, // many files will have multiple clients in this case.  We can speed up allocation here
        );
        try client_array.append(client_addr);

        var chunk_array = std.ArrayList(ChunkInfo).init(self.alloc);

        if (chunk_hashes) |chunks| {
            for (chunks) |chunk| {
                try chunk_array.append(.{
                    .chunkName = try self.alloc.dupe(u8, chunk.chunkName),
                    .chunkSize = chunk.chunkSize,
                });
            }
        }

        const index = try self.files.addOne(self.alloc);
        self.files.set(index, .{
            .filename = try self.alloc.dupe(u8, filename),
            .fullFileHash = my_hash,
            .fileSize = fileSize,
            .clientIPs = client_array,
            .chunk_hashes = chunk_array,
        });

        // update lookup system
        self.filter.add(my_hash);
        try self.map.put(my_hash, index);
    }

    /// Given a file hash, return the list of clients that have it
    pub fn getClients(self: *Self, hash: []const u8) !?[]std.net.Address {

        // quick negitive lookup
        if (!self.filter.contains(hash)) return null;

        if (self.map.get(hash)) |file_index| {
            const client_list = self.files.slice().items(.clientIPs)[file_index];

            var results = try std.ArrayList(std.net.Address).initCapacity(
                self.alloc,
                client_list.items.len,
            );
            try results.appendSlice(client_list.items);
            return try results.toOwnedSlice();
        }

        // the bloomfilter can make mistakes, so if it isnt in the map
        // then we should still return nothing.
        log.warn("bloomfilter falsepos in search for hash {s}", .{hash});
        return null;
    }

    /// Given a file hash, return the chunks it is made from
    pub fn getChunks(self: *Self, hash: []const u8) !?[]ChunkInfo {
        if (!self.filter.contains(hash)) return null;

        if (self.map.get(hash)) |file_index| {
            const chunks = self.files.slice().items(.chunk_hashes)[file_index];

            var result = try std.ArrayList(ChunkInfo).initCapacity(
                self.alloc,
                chunks.items.len,
            );

            for (chunks.items) |chunk| {
                try result.append(.{
                    .chunkName = try self.alloc.dupe(u8, chunk.chunkName),
                    .chunkSize = chunk.chunkSize,
                });
            }

            return result.toOwnedSlice();
        }

        return null;
    }

    /// Given an index, return the file hash
    pub fn getHashIdx(self: *Self, idx: usize, alloc: std.mem.Allocator) !?[]const u8 {
        const slice = self.files.slice();

        if (idx >= slice.items(.fullFileHash).len) return null;

        return try alloc.dupe(u8, slice.items(.fullFileHash)[idx]);
    }

    pub fn fileCount(self: Self) usize {
        return self.files.len;
    }

    pub fn totalFileClientRelationships(self: Self) usize {
        var total: usize = 0;
        const client_list = self.files.slice().items(.clientIPs);

        for (client_list) |list| {
            total += list.items.len;
        }
        return total;
    }

    pub fn getStats(self: Self) struct {
        fileCount: usize,
        clientRelationships: usize,
        averageClientsPerFile: f32,
        bloomFilterSize: usize,
        bloomFilterHashFunctions: usize,
    } {
        const file_count = self.fileCount();
        const relationships = self.totalFileClientRelationships();
        const avg_client_per_file = if (file_count > 0) @as(f32, @floatFromInt(relationships)) / @as(f32, @floatFromInt(file_count)) else 0;

        return .{
            .fileCount = file_count,
            .clientRelationships = relationships,
            .averageClientsPerFile = avg_client_per_file,
            .bloomFilterSize = n_bits,
            .bloomFilterHashFunctions = K,
        };
    }

    fn serializeFile(self: *Self, file: FileData, writer: anytype) !void {
        var ip_strings = std.ArrayList([]const u8).init(self.alloc);
        defer ip_strings.deinit();

        for (file.clientIPs.items) |addr| {
            var buf: [64]u8 = undefined;
            const ip_str = try std.fmt.bufPrint(&buf, "{}", .{addr});
            try ip_strings.append(try std.heap.page_allocator.dupe(u8, ip_str));
        }

        try std.json.stringify(
            .{
                .filename = file.filename,
                .fullFileHash = file.fullFileHash,
                .clientIPs = ip_strings.items,
                .peerCount = file.clientIPs.items.len,
            },
            .{},
            writer,
        );

        for (ip_strings.items) |str| {
            std.heap.page_allocator.free(str);
        }
    }

    pub fn serialize(self: *Self, writer: anytype) !void {
        try writer.writeAll("[\n");

        const slice = self.files.slice();

        for (0..self.files.len) |i| {
            const file = FileData{
                .filename = slice.items(.filename)[i],
                .fullFileHash = slice.items(.fullFileHash)[i],
                .fileSize = slice.items(.fileSize)[i],
                .clientIPs = slice.items(.clientIPs)[i],
                .chunk_hashes = slice.items(.chunk_hashes)[i],
            };
            try self.serializeFile(file, writer);

            if (i < self.files.len - 1) {
                try writer.writeAll(",\n");
            }
        }
        try writer.writeAll("\n]");
    }

    pub fn queryResponse(self: *Self, writer: anytype) !void {
        try writer.writeAll("{\"requestType\": \"queryResponse\", \"files\":[\n");

        const slice = self.files.slice();

        for (0..self.files.len) |i| {
            var clients = std.ArrayList(struct {
                IP: []const u8,
                Port: []const u8,
            }).init(self.alloc);

            for (slice.items(.clientIPs)[i].items) |client| {
                var ip_buf: [64]u8 = undefined;
                var port_buf: [16]u8 = undefined;

                const bytes = @as(*const [4]u8, @ptrCast(&client.in.sa.addr));
                const ip = try std.fmt.bufPrint(&ip_buf, "{}.{}.{}.{}", .{
                    bytes[0],
                    bytes[1],
                    bytes[2],
                    bytes[3],
                });

                const port = try std.fmt.bufPrint(&port_buf, "{d}", .{client.getPort()});

                try clients.append(.{
                    .IP = try self.alloc.dupe(u8, ip),
                    .Port = try self.alloc.dupe(u8, port),
                });
            }
            defer {
                for (clients.items) |item| {
                    self.alloc.free(item.IP);
                    self.alloc.free(item.Port);
                }
                clients.deinit();
            }

            try std.json.stringify(
                .{
                    .filename = slice.items(.filename)[i],
                    .fullFileHash = slice.items(.fullFileHash)[i],
                    .fileSize = slice.items(.fileSize)[i],
                    .numberOfPeers = slice.items(.clientIPs)[i].items.len,
                    .numberOfChunks = slice.items(.chunk_hashes)[i].items.len,
                    .chunk_hashes = slice.items(.chunk_hashes)[i].items,
                    .IPInfo = clients.items,
                },
                .{},
                writer,
            );

            if (i < self.files.len - 1) {
                try writer.writeAll(",\n");
            }
        }
        try writer.writeAll("\n]}");
    }

    pub fn printTable(self: *Self, writer: anytype) !void {
        const slice = self.files.slice();

        for (0..self.files.len) |i| {
            try writer.print("{s:<20}{s:<}\n", .{ "filename", slice.items(.filename)[i] });
            try writer.print("{s:<20}{s:<}\n", .{ "fileHash", slice.items(.fullFileHash)[i] });

            for (slice.items(.clientIPs)[i].items) |addr| {
                var buf: [64]u8 = undefined;
                const ip_str = try std.fmt.bufPrint(&buf, "{}", .{addr});
                try writer.print("{s:<20}{s:<}\n", .{ "", ip_str });
            }
            try writer.writeAll("\n");
        }
        try writer.writeAll("\n");
    }

    pub fn printSimpleTable(self: *Self, writer: anytype) !void {
        const slice = self.files.slice();
        try writer.writeAll("\n==========================\n");
        for (0.., slice.items(.filename), slice.items(.fullFileHash), slice.items(.fileSize)) |i, filename, hash, size| {
            try writer.print("{d} {s} {d}bytes \n\t{s}\n", .{ i, filename, size, hash });
        }
        try writer.writeAll("\n");
    }
};

test "FileRegistry - basic functionality" {
    var reg = try FileRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const filename1 = "myfilename";
    const filename2 = "anotherfile";
    const hash1 = "myfilehash0000000000000000000000";
    const hash2 = "differenthash0000000000000000000";
    const client_addr1 = try std.net.Address.parseIp4("127.0.0.1", 10423);
    const client_addr2 = try std.net.Address.parseIp4("192.168.1.10", 8080);

    try reg.registerFile(filename1, 10, hash1, client_addr1, null);
    try reg.registerFile(filename1, 10, hash1, client_addr2, null);
    try reg.registerFile(filename2, 10, hash2, client_addr1, null);

    const hash1clients = try reg.getClients(hash1);
    defer if (hash1clients) |hash| reg.alloc.free(hash);

    try std.testing.expectEqual(hash1clients.?.len, 2);
    try std.testing.expectEqual(hash1clients.?[0].getPort(), client_addr1.getPort());
    try std.testing.expectEqual(hash1clients.?[1].getPort(), client_addr2.getPort());

    const nonexistent = try reg.getClients("nonexistenthash00000000000000");
    defer if (nonexistent) |hash| reg.alloc.free(hash);

    if (nonexistent) |_| {
        try std.testing.expect(false); // if this fails then it returned a file
        unreachable;
    }

    const stats = reg.getStats();
    try std.testing.expectEqual(stats.fileCount, 2);
    try std.testing.expectEqual(stats.clientRelationships, 3);
    try std.testing.expectApproxEqAbs(stats.averageClientsPerFile, 1.5, 0.01);
}

test "FileRegistry - duplicate registration" {
    var reg = try FileRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const filename = "testfile";
    const hash = "testhash000000000000000000000";
    const client_addr = try std.net.Address.parseIp4("127.0.0.1", 10423);

    try reg.registerFile(filename, 10, hash, client_addr, null);
    try reg.registerFile(filename, 10, hash, client_addr, null);

    const clients = try reg.getClients(hash) orelse {
        try std.testing.expect(false);
        unreachable;
    };
    defer reg.alloc.free(clients);

    try std.testing.expectEqual(clients.len, 1);
    try std.testing.expectEqual(clients[0].getPort(), client_addr.getPort());

    const stats = reg.getStats();
    try std.testing.expectEqual(stats.fileCount, 1);
    try std.testing.expectEqual(stats.clientRelationships, 1);
}

test "FileRegistry - serialization" {
    var reg = try FileRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const filename = "testfile";
    const hash = "testhash000000000000000000000";
    const client_addr = try std.net.Address.parseIp4("127.0.0.1", 10423);

    try reg.registerFile(filename, 10, hash, client_addr, null);

    // Serialize to buf instead of stdout
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try reg.serialize(buffer.writer());

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, filename) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, hash) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "127.0.0.1") != null);
}

test "FileRegistry - queryResponse" {
    var reg = try FileRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const filename = "testfile";
    const hash = "testhash000000000000000000000";
    const client_addr = try std.net.Address.parseIp4("127.0.0.1", 10423);

    const chunks = [_]FileRegistry.ChunkInfo{
        .{ .chunkName = "chunk1", .chunkSize = 100 },
        .{ .chunkName = "chunk2", .chunkSize = 200 },
    };

    try reg.registerFile(filename, 10, hash, client_addr, &chunks);

    // Serialize to buf instead of stdout
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try reg.queryResponse(buffer.writer());

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, filename) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, hash) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "127.0.0.1") != null);
}
