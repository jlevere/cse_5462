const std = @import("std");
const ArrayLinkedList = @import("array_linked_list.zig").ArrayLinkedList;
const bflib = @import("bloom_filter.zig");
const BloomFilter = bflib.BloomFilter;

const wyhash = bflib.wyhash;

/// Repersentation of a remote file for the server
const RemoteFile = struct {
    const Self = @This();

    filename: []const u8,
    fullFileHash: []const u8,
    clientIP: std.ArrayList(std.net.Address),

    pub fn serialize(self: Self, writer: anytype) !void {
        try std.json.stringify(
            .{
                .filename = self.filename,
                .fullFileHash = self.fullFileHash,
                .clientIP = self.clientIP.items[0].any.data,
            },
            .{},
            writer,
        );
    }
};

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

    files: ArrayLinkedList(RemoteFile),
    filter: BloomFilter(n_bits, K, wyhash),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{
            .files = ArrayLinkedList(RemoteFile).init(alloc),
            .alloc = alloc,
            .filter = BloomFilter(
                n_bits,
                K,
                wyhash,
            ){},
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.files.iterator();
        while (it.next()) |node| {
            self.alloc.free(node.data.filename);
            self.alloc.free(node.data.fullFileHash);
            node.data.clientIP.deinit();
        }
        self.files.deinit();
    }

    /// Register a new client
    pub fn registerClient() void {}

    /// Regster a new file
    pub fn registerFile(self: *Self, filename: []const u8, hash: []const u8, client_addr: std.net.Address) !void {
        const my_hash = try self.alloc.dupe(u8, hash);

        var client_array = std.ArrayList(std.net.Address).init(self.alloc);
        try client_array.append(client_addr);

        try self.files.append(.{
            .filename = try self.alloc.dupe(u8, filename),
            .fullFileHash = my_hash,
            .clientIP = client_array,
        });

        self.filter.add(my_hash);
    }

    /// Search for clents by filehash
    pub fn search(self: *Self, hash: []const u8) ![]std.net.Address {
        if (!self.filter.contains(hash)) return &.{};

        var results = std.ArrayList(std.net.Address).init(self.alloc);
        var it = self.files.iterator();
        while (it.next()) |node| {
            if (std.mem.eql(u8, node.data.fullFileHash, hash)) {
                try results.appendSlice(node.data.clientIP);
            }
        }

        return results.toOwnedSlice();
    }
};

test "FileRegistry - basic" {
    var reg = try FileRegistry.init(std.testing.allocator);
    defer reg.deinit();

    const filename = "myfilename";
    const hash = "myfilehash0000000000000000000000";
    const client_addr = try std.net.Address.parseIp4("127.0.0.1", 10423);

    try reg.registerFile(filename, hash, client_addr);

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var iter = reg.files.iterator();

    std.debug.print("about to print nodes\n", .{});

    while (iter.next()) |node| {
        try node.data.serialize(stdout);
    }
}
