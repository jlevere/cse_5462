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

    pub const FileData = struct {
        filename: []const u8,
        fullFileHash: []const u8,
        clientIPs: std.ArrayList(std.net.Address),
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

        for (slice.items(.filename), slice.items(.fullFileHash), slice.items(.clientIPs)) |filename, hash, *client_list| {
            self.alloc.free(filename);
            self.alloc.free(hash);
            client_list.deinit();
        }
        self.files.deinit(self.alloc);
        self.map.deinit();
    }

    /// Register a new client
    pub fn registerClient() void {}

    /// Regster a new file
    pub fn registerFile(self: *Self, filename: []const u8, hash: []const u8, client_addr: std.net.Address) !void {

        // If the file already exists
        if (self.filter.contains(hash)) {
            if (self.map.get(hash)) |file_index| {
                var client_list = &self.files.slice().items(.clientIPs)[file_index];

                for (client_list.items) |addr| {
                    if (std.mem.eql(u8, &addr.any.data, &client_addr.any.data)) {
                        return; // Client already registered to this file
                    }
                }

                // add the new client to file
                try client_list.append(client_addr);
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

        const index = try self.files.addOne(self.alloc);
        self.files.set(index, .{
            .filename = try self.alloc.dupe(u8, filename),
            .fullFileHash = my_hash,
            .clientIPs = client_array,
        });

        // update lookup system
        self.filter.add(my_hash);
        try self.map.put(my_hash, index);
    }

    /// Search for clents by filehash
    pub fn search(self: *Self, hash: []const u8) ![]std.net.Address {

        // quick negitive lookup
        if (!self.filter.contains(hash)) return &.{};

        if (self.map.get(hash)) |file_index| {
            const client_list = self.files.slice().items(.clientIPs)[file_index];

            var results = try std.ArrayList(std.net.Address).initCapacity(
                self.alloc,
                client_list.items.len,
            );
            try results.appendSlice(client_list.items);
            return results.toOwnedSlice();
        }

        // the bloomfilter can make mistakes, so if it isnt in the map
        // then we should still return nothing.
        log.warn("bloomfilter falsepos in search for hash {s}", .{hash});
        return &.{};
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
                .clientIPs = slice.items(.clientIPs)[i],
            };
            try self.serializeFile(file, writer);

            if (i < self.files.len - 1) {
                try writer.writeAll(",\n");
            }
        }
        try writer.writeAll("\n]");
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

    try reg.registerFile(filename1, hash1, client_addr1);
    try reg.registerFile(filename1, hash1, client_addr2);
    try reg.registerFile(filename2, hash2, client_addr1);

    const hash1clients = try reg.search(hash1);
    defer reg.alloc.free(hash1clients);

    try std.testing.expectEqual(hash1clients.len, 2);
    try std.testing.expectEqual(hash1clients[0].getPort(), client_addr1.getPort());
    try std.testing.expectEqual(hash1clients[1].getPort(), client_addr2.getPort());

    const nonexistent = try reg.search("nonexistenthash00000000000000");
    defer reg.alloc.free(nonexistent);
    try std.testing.expectEqual(nonexistent.len, 0);

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

    try reg.registerFile(filename, hash, client_addr);
    try reg.registerFile(filename, hash, client_addr);

    const clients = try reg.search(hash);
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

    try reg.registerFile(filename, hash, client_addr);

    // Serialize to buf instead of stdout
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try reg.serialize(buffer.writer());

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, filename) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, hash) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "127.0.0.1") != null);
}
