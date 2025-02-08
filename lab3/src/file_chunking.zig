const std = @import("std");

const File = struct {
    const Self = @This();
    const Allocator = std.mem.Allocator;

    alloc: Allocator,
    filename: []const u8,
    fileSize: usize,
    chunk_hashes: std.ArrayList([]const u8),
    fullFileHash: []const u8,

    pub fn init(
        alloc: Allocator,
        filename: []const u8,
        fileSize: usize,
        chunk_hashes: []const []const u8,
        fullFileHash: []const u8,
    ) !Self {
        var self: File = .{
            .alloc = alloc,
            .filename = try alloc.dupe(u8, filename),
            .fileSize = fileSize,
            .chunk_hashes = undefined,
            .fullFileHash = try alloc.dupe(u8, fullFileHash),
        };
        errdefer self.deinit();

        self.chunk_hashes = std.ArrayList([]const u8).init(alloc);
        try self.chunk_hashes.ensureTotalCapacity(chunk_hashes.len);

        for (chunk_hashes) |hash| {
            self.chunk_hashes.appendAssumeCapacity(try alloc.dupe(u8, hash));
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.filename);
        self.alloc.free(self.fullFileHash);

        for (self.chunk_hashes.items) |hash| {
            self.alloc.free(hash);
        }
        self.chunk_hashes.deinit();
    }

    /// Serialize the file object into a serialized json string
    pub fn serialize(self: Self, writer: anytype) !void {
        try std.json.stringify(.{
            .filename = self.filename,
            .fileSize = self.fileSize,
            .numberOfChunks = self.chunk_hashes.items.len,
            .chunk_hashes = self.chunk_hashes.items,
            .fullFileHash = self.fullFileHash,
        }, .{}, writer);
    }

    pub const FromJson = struct {
        pub fn parse(alloc: Allocator, data: []const u8) !File {
            const parsed = try std.json.parseFromSlice(
                struct {
                    filename: []const u8,
                    fileSize: usize,
                    numberOfChunks: usize,
                    chunk_hashes: [][]const u8,
                    fullFileHash: []const u8,
                },
                alloc,
                data,
                .{ .allocate = .alloc_always },
            );
            defer parsed.deinit();

            return File.init(
                alloc,
                parsed.value.filename,
                parsed.value.fileSize,
                parsed.value.chunk_hashes,
                parsed.value.fullFileHash,
            );
        }
    };
};

test "File deserialize" {
    var chunk_hashes = std.ArrayList([]const u8).init(std.testing.allocator);
    defer chunk_hashes.deinit();
    try chunk_hashes.append("a1b2c3d4");
    try chunk_hashes.append("e5f6g7h8");
    try chunk_hashes.append("i9j0k1l2");
    try chunk_hashes.append("m3n4o5p6");

    var expected = try File.init(
        std.testing.allocator,
        "example.txt",
        1024,
        chunk_hashes.items,
        "abcdef1234567890",
    );
    defer expected.deinit();

    const data: []const u8 =
        \\ {
        \\  "filename": "example.txt",
        \\  "fileSize": 1024,
        \\  "numberOfChunks": 4,
        \\  "chunk_hashes": [
        \\      "a1b2c3d4",
        \\      "e5f6g7h8",
        \\      "i9j0k1l2",
        \\      "m3n4o5p6"
        \\  ],
        \\  "fullFileHash": "abcdef1234567890"
        \\ }
    ;

    var parsed = try File.FromJson.parse(std.testing.allocator, data);
    defer parsed.deinit();

    try std.testing.expectEqualStrings(expected.filename, parsed.filename);
    try std.testing.expectEqual(expected.fileSize, parsed.fileSize);
    try std.testing.expectEqualStrings(expected.fullFileHash, parsed.fullFileHash);

    for (expected.chunk_hashes.items, parsed.chunk_hashes.items) |valid, result| {
        try std.testing.expectEqualStrings(valid, result);
    }
}

test "File serialize" {
    var chunk_hashes = std.ArrayList([]const u8).init(std.testing.allocator);
    defer chunk_hashes.deinit();
    try chunk_hashes.append("a1b2c3d4");
    try chunk_hashes.append("e5f6g7h8");

    var file = try File.init(
        std.testing.allocator,
        "test.txt",
        512,
        chunk_hashes.items,
        "1234567890abcdef",
    );
    defer file.deinit();

    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try file.serialize(list.writer());

    const expected =
        \\{"filename":"test.txt","fileSize":512,"numberOfChunks":2,"chunk_hashes":["a1b2c3d4","e5f6g7h8"],"fullFileHash":"1234567890abcdef"}
    ;

    try std.testing.expectEqualStrings(expected, list.items);
}

test "File end-to-end serialization" {
    var initial_chunks = std.ArrayList([]const u8).init(std.testing.allocator);
    defer initial_chunks.deinit();
    try initial_chunks.append("hash1");
    try initial_chunks.append("hash2");
    try initial_chunks.append("hash3");

    var original = try File.init(
        std.testing.allocator,
        "document.txt",
        2048,
        initial_chunks.items,
        "totalhash123",
    );
    defer original.deinit();

    var json_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer json_buffer.deinit();
    try original.serialize(json_buffer.writer());

    var deserialized = try File.FromJson.parse(std.testing.allocator, json_buffer.items);
    defer deserialized.deinit();

    try std.testing.expectEqualStrings(original.filename, deserialized.filename);
    try std.testing.expectEqual(original.fileSize, deserialized.fileSize);
    try std.testing.expectEqualStrings(original.fullFileHash, deserialized.fullFileHash);
    try std.testing.expectEqual(original.chunk_hashes.items.len, deserialized.chunk_hashes.items.len);

    for (original.chunk_hashes.items, deserialized.chunk_hashes.items) |orig, des| {
        try std.testing.expectEqualStrings(orig, des);
    }

    var verification_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer verification_buffer.deinit();
    try deserialized.serialize(verification_buffer.writer());

    try std.testing.expectEqualStrings(json_buffer.items, verification_buffer.items);
}
