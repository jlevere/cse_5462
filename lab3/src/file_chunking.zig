const std = @import("std");

const log = std.log.scoped(.file_chunking);

pub const File = struct {
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

    /// Iterator over manifest files in a given directory
    pub const Iterator = struct {
        allocator: std.mem.Allocator,
        dir: std.fs.Dir,
        inner_iterator: std.fs.Dir.Iterator,
        current: ?*File,

        pub fn init(allocator: std.mem.Allocator, dir: std.fs.Dir) Iterator {
            return .{
                .allocator = allocator,
                .dir = dir,
                .inner_iterator = dir.iterate(),
                .current = null,
            };
        }
        pub fn deinit(self: *Iterator) void {
            if (self.current) |file| {
                file.deinit();
                self.allocator.destroy(file);
            }
        }

        pub fn next(self: *File.Iterator) !?*File {
            if (self.current) |file| {
                file.deinit();
                self.allocator.destroy(file);
                self.current = null;
            }

            while (try self.inner_iterator.next()) |entry| {
                if (entry.kind != .file) continue;
                if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

                const file = try self.dir.openFile(entry.name, .{});
                defer file.close();

                const contents = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
                defer self.allocator.free(contents);

                const new_file = try self.allocator.create(File);
                errdefer self.allocator.destroy(new_file);

                new_file.* = try File.FromJson.parse(self.allocator, contents);
                self.current = new_file;
                return new_file;
            }
            return null;
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

pub const ChunkDir = struct {
    const Self = @This();
    const Allocator = std.mem.Allocator;
    const Sha256 = std.crypto.hash.sha2.Sha256;

    const CHUNK_SIZE: usize = 500 * 1024; // 500 KB

    alloc: Allocator,
    dir: std.fs.Dir,
    cache: ?std.fs.Dir,
    cache_name: []const u8,

    pub fn init(
        alloc: Allocator,
        dir: std.fs.Dir,
        cache_name: []const u8,
    ) !Self {
        return .{
            .alloc = alloc,
            .dir = dir,
            .cache = null,
            .cache_name = cache_name,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.cache) |*cache_dir| {
            cache_dir.close();
            self.cache = null;
        }
    }

    /// Deletes the subdirectory of `dir` named `self.cache_name` and every file inside it.
    /// It is assumed that there are no directories in `self.cache_name`
    pub fn clearCache(self: *Self) !void {
        var cache = try self.dir.openDir(self.cache_name, .{ .iterate = true });

        var iter = cache.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) {
                continue;
            }
            try cache.deleteFile(entry.name);
        }
        cache.close();

        try self.dir.deleteDir(self.cache_name);
    }

    /// Check if the cache directory exists already
    pub fn cacheExists(self: *Self) !bool {
        const stat = self.dir.statFile(self.cache_name) catch |err| switch (err) {
            error.FileNotFound => return false,
            error.AccessDenied => return error.AccessDenied,
            else => |e| return e,
        };

        return stat.kind == .directory;
    }

    /// Creates a subdirectory in `dir` named `self.cache_name` to be used as a cache
    pub fn createCacheDir(self: *Self) !void {
        self.dir.makeDir(self.cache_name) catch |err| switch (err) {
            error.PathAlreadyExists => {
                return error.CacheDirAlreadyExists;
            },
            else => return err,
        };
        self.cache = try self.dir.openDir(self.cache_name, .{});
    }

    /// Given a filename, break it up into 500kb chunks, write them into
    /// the cache directory, and write a manafest file as well.
    pub fn chunkFile(self: Self, filename: []const u8) !void {
        const thisfile = try self.dir.openFile(
            filename,
            .{ .mode = .read_only },
        );
        defer thisfile.close();

        const fullFileHash_bytes = try hash_file(thisfile);
        const fullFileHash = try std.fmt.allocPrint(self.alloc, "{s}", .{std.fmt.fmtSliceHexLower(&fullFileHash_bytes)});
        defer self.alloc.free(fullFileHash);

        log.info("cache created: {any}", .{if (self.cache) |_| true else false});

        if (self.cache) |cache| {
            try thisfile.seekTo(0);
            var filereader = thisfile.reader();

            var chunk_hashes = std.ArrayList([]const u8).init(self.alloc);
            defer {
                for (chunk_hashes.items) |hash| self.alloc.free(hash);
                chunk_hashes.deinit();
            }

            var buf: [CHUNK_SIZE]u8 = undefined;
            while (true) {
                const n = try filereader.read(&buf);
                if (n == 0) break;

                var sha = std.crypto.hash.sha2.Sha256.init(.{});
                sha.update(buf[0..n]);

                const chunkfilename = try std.fmt.allocPrint(self.alloc, "{s}", .{std.fmt.fmtSliceHexLower(&sha.finalResult())});
                defer self.alloc.free(chunkfilename);

                try chunk_hashes.append(try self.alloc.dupe(u8, chunkfilename));

                var chunk_file = try cache.createFile(chunkfilename, .{});
                defer chunk_file.close();

                try chunk_file.writeAll(buf[0..n]);

                log.info("write chunk {s} of {d} bytes", .{ chunkfilename, n });
            }

            const manifest_name = try std.fmt.allocPrint(self.alloc, "{s}.json", .{fullFileHash});
            defer self.alloc.free(manifest_name);

            var fileobj = try File.init(
                self.alloc,
                filename,
                100,
                chunk_hashes.items,
                fullFileHash,
            );
            defer fileobj.deinit();

            var json_buffer = std.ArrayList(u8).init(self.alloc);
            defer json_buffer.deinit();
            try fileobj.serialize(json_buffer.writer());

            var manafest = try cache.createFile(manifest_name, .{});
            try manafest.writeAll(json_buffer.items);
            manafest.close();
        }
    }

    pub fn buildCache(self: Self) !void {
        var iter = self.dir.iterate();

        while (try iter.next()) |entry| {
            if (entry.kind != .file) {
                continue;
            }

            try self.chunkFile(entry.name);
        }
        log.debug("finished building cache", .{});
    }
};

pub fn hash_file(file: std.fs.File) ![std.crypto.hash.sha2.Sha256.digest_length]u8 {
    var sha = std.crypto.hash.sha2.Sha256.init(.{});
    const reader = file.reader();

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try reader.read(&buf);
        if (n == 0) break;
        sha.update(buf[0..n]);
    }
    return sha.finalResult();
}

test "hash_file empty file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file_path = try tmp_dir.dir.createFile(
        "empty.txt",
        .{ .read = true },
    );
    defer file_path.close();

    const hash = try hash_file(file_path);

    const empty_file_hash = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };

    try std.testing.expectEqualSlices(u8, &empty_file_hash, &hash);
}

test "hash_file known content" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile(
        "test.txt",
        .{ .read = true },
    );
    defer file.close();

    const writer = file.writer();
    try writer.writeAll("hi fren :3");
    try file.seekTo(0);

    const hash = try hash_file(file);

    const known_hash = [_]u8{
        0xa4, 0xb1, 0xc5, 0x80, 0x84, 0x5f, 0xe3, 0xad,
        0x48, 0xae, 0xdb, 0xe8, 0x19, 0xf3, 0x61, 0xf0,
        0x4b, 0x18, 0x9b, 0xc1, 0x70, 0xf2, 0x18, 0x49,
        0x39, 0xf3, 0xef, 0xe7, 0x2a, 0xdf, 0x64, 0x3a,
    };

    try std.testing.expectEqualSlices(u8, &known_hash, &hash);
}

test "hash_file large file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile(
        "large.txt",
        .{ .read = true },
    );
    defer file.close();

    const writer = file.writer();
    var i: usize = 0;
    while (i < 8192) : (i += 1) {
        try writer.writeAll("A");
    }
    try file.seekTo(0);

    _ = try hash_file(file);
}
