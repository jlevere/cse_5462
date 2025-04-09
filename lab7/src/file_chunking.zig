const std = @import("std");

const log = std.log.scoped(.file_chunking);

pub const File = struct {
    const Self = @This();
    const Allocator = std.mem.Allocator;

    pub const ChunkInfo = struct {
        chunkName: []const u8,
        chunkSize: i64,
    };

    alloc: Allocator,
    filename: []const u8,
    fileSize: usize,
    chunk_hashes: std.ArrayList(ChunkInfo),
    fullFileHash: []const u8,

    pub fn init(
        alloc: Allocator,
        filename: []const u8,
        fileSize: usize,
        chunk_hashes: []ChunkInfo,
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

        self.chunk_hashes = std.ArrayList(ChunkInfo).init(alloc);
        try self.chunk_hashes.ensureTotalCapacity(chunk_hashes.len);

        for (chunk_hashes) |chunk| {
            self.chunk_hashes.appendAssumeCapacity(.{
                .chunkName = try alloc.dupe(u8, chunk.chunkName),
                .chunkSize = chunk.chunkSize,
            });
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.alloc.free(self.filename);
        self.alloc.free(self.fullFileHash);

        for (self.chunk_hashes.items) |chunk| {
            self.alloc.free(chunk.chunkName);
        }
        self.chunk_hashes.deinit();
    }

    /// Serialize the file object into a serialized json string
    pub fn serialize(self: Self, writer: anytype, extra_fields: ?std.StringHashMap([]const u8)) !void {
        var jw = std.json.writeStream(
            writer,
            .{},
        );

        try jw.beginObject();

        // add any extra fields first
        if (extra_fields) |fields| {
            var iter = fields.iterator();
            while (iter.next()) |entry| {
                try jw.objectField(entry.key_ptr.*);
                try jw.write(entry.value_ptr.*);
            }
        }

        inline for (.{
            .{ "filename", self.filename },
            .{ "fileSize", self.fileSize },
            .{ "numberOfChunks", self.chunk_hashes.items.len },
            .{ "fullFileHash", self.fullFileHash },
        }) |field| {
            try jw.objectField(field[0]);
            try jw.write(field[1]);
        }

        try jw.objectField("chunk_hashes");
        try jw.beginArray();
        for (self.chunk_hashes.items) |hash| {
            try jw.beginObject();

            try jw.objectField("chunkName");
            try jw.write(hash.chunkName);

            try jw.objectField("chunkSize");
            try jw.write(hash.chunkSize);
            try jw.endObject();
        }
        try jw.endArray();

        try jw.endObject();
    }

    pub const FromJson = struct {
        pub fn parse(alloc: Allocator, data: []const u8) !File {
            const parsed = try std.json.parseFromSlice(
                struct {
                    filename: []const u8,
                    fileSize: usize,
                    numberOfChunks: usize,
                    chunk_hashes: []ChunkInfo,
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
    var chunk_hashes = std.ArrayList(File.ChunkInfo).init(std.testing.allocator);
    defer chunk_hashes.deinit();
    try chunk_hashes.append(.{ .chunkName = "a1b2c3d4", .chunkSize = 1 });
    try chunk_hashes.append(.{ .chunkName = "e5f6g7h8", .chunkSize = 2 });

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
        \\      {
        \\         "chunkName": "a1b2c3d4",
        \\         "chunkSize": 1
        \\      },
        \\      {
        \\          "chunkName": "e5f6g7h8",
        \\          "chunkSize": 2
        \\      }
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
        try std.testing.expectEqualStrings(valid.chunkName, result.chunkName);
        try std.testing.expectEqual(valid.chunkSize, result.chunkSize);
    }
}

test "File serialize" {
    var chunk_hashes = std.ArrayList(File.ChunkInfo).init(std.testing.allocator);
    defer chunk_hashes.deinit();
    try chunk_hashes.append(.{ .chunkName = "a1b2c3d4", .chunkSize = 1 });
    try chunk_hashes.append(.{ .chunkName = "e5f6g7h8", .chunkSize = 2 });

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

    try file.serialize(list.writer(), null);

    const expected =
        \\{"filename":"test.txt","fileSize":512,"numberOfChunks":2,"fullFileHash":"1234567890abcdef","chunk_hashes":[{"chunkName":"a1b2c3d4","chunkSize":1},{"chunkName":"e5f6g7h8","chunkSize":2}]}
    ;

    try std.testing.expectEqualStrings(expected, list.items);
}

test "File end-to-end serialization" {
    var chunk_hashes = std.ArrayList(File.ChunkInfo).init(std.testing.allocator);
    defer chunk_hashes.deinit();
    try chunk_hashes.append(.{ .chunkName = "a1b2c3d4", .chunkSize = 1 });
    try chunk_hashes.append(.{ .chunkName = "e5f6g7h8", .chunkSize = 2 });

    var original = try File.init(
        std.testing.allocator,
        "document.txt",
        2048,
        chunk_hashes.items,
        "totalhash123",
    );
    defer original.deinit();

    var json_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer json_buffer.deinit();
    try original.serialize(json_buffer.writer(), null);

    var deserialized = try File.FromJson.parse(std.testing.allocator, json_buffer.items);
    defer deserialized.deinit();

    try std.testing.expectEqualStrings(original.filename, deserialized.filename);
    try std.testing.expectEqual(original.fileSize, deserialized.fileSize);
    try std.testing.expectEqualStrings(original.fullFileHash, deserialized.fullFileHash);
    try std.testing.expectEqual(original.chunk_hashes.items.len, deserialized.chunk_hashes.items.len);

    for (original.chunk_hashes.items, deserialized.chunk_hashes.items) |orig, des| {
        try std.testing.expectEqualStrings(orig.chunkName, des.chunkName);
        try std.testing.expectEqual(orig.chunkSize, des.chunkSize);
    }

    var verification_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer verification_buffer.deinit();
    try deserialized.serialize(verification_buffer.writer(), null);

    try std.testing.expectEqualStrings(json_buffer.items, verification_buffer.items);
}

pub const ChunkDir = struct {
    const Self = @This();
    const Allocator = std.mem.Allocator;
    const Sha256 = std.crypto.hash.sha2.Sha256;

    const CHUNK_SIZE: usize = 500 * 1024; // 500 KB

    alloc: Allocator,
    dir: std.fs.Dir,
    cache_name: []const u8,

    pub fn init(
        alloc: Allocator,
        dir: std.fs.Dir,
        cache_name: []const u8,
    ) !Self {
        return .{
            .alloc = alloc,
            .dir = dir,
            .cache_name = cache_name,
        };
    }

    /// Deletes the subdirectory of `dir` named `self.cache_name` and every file inside it.
    /// It is assumed that there are no directories in `self.cache_name`
    pub fn clearCache(self: *Self) !void {
        var cache = try self.dir.openDir(self.cache_name, .{
            .iterate = true,
            .access_sub_paths = true,
        });
        defer cache.close();

        var iter = cache.iterate();
        while (try iter.next()) |entry| {
            try cache.deleteFile(entry.name);
        }

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
    }

    /// Given a filename, break it up into 500kb chunks, write them into
    /// the cache directory, and write a manafest file as well.
    pub fn chunkFile(self: Self, filename: []const u8) !void {
        const thisfile = try self.dir.openFile(
            filename,
            .{ .mode = .read_only },
        );
        defer thisfile.close();

        var cache = try self.dir.openDir(self.cache_name, .{ .iterate = true });
        defer cache.close();

        try thisfile.seekTo(0);
        var filereader = thisfile.reader();

        var chunk_hashes = std.ArrayList(File.ChunkInfo).init(self.alloc);
        defer {
            for (chunk_hashes.items) |chunk| self.alloc.free(chunk.chunkName);
            chunk_hashes.deinit();
        }

        var buf: [CHUNK_SIZE]u8 = undefined;
        var fullSha = std.crypto.hash.sha2.Sha256.init(.{});
        while (true) {
            const n = try filereader.read(&buf);
            if (n == 0) break;

            var sha = std.crypto.hash.sha2.Sha256.init(.{});
            sha.update(buf[0..n]);
            fullSha.update(buf[0..n]);

            const chunkfilename = try std.fmt.allocPrint(
                self.alloc,
                "{s}",
                .{std.fmt.fmtSliceHexLower(&sha.finalResult())},
            );
            try chunk_hashes.append(.{
                .chunkName = chunkfilename,
                .chunkSize = @as(i64, @intCast(n)),
            });

            var chunk_file = try cache.createFile(chunkfilename, .{});
            defer chunk_file.close();

            try chunk_file.writeAll(buf[0..n]);

            log.info("write chunk of {s:<20} {d} bytes", .{ filename, n });
        }

        const fullFileHash = try std.fmt.allocPrint(
            self.alloc,
            "{s}",
            .{std.fmt.fmtSliceHexLower(&fullSha.finalResult())},
        );
        defer self.alloc.free(fullFileHash);

        const manifest_name = try std.fmt.allocPrint(self.alloc, "{s}.json", .{fullFileHash});
        defer self.alloc.free(manifest_name);

        var fileobj = try File.init(
            self.alloc,
            filename,
            (try thisfile.stat()).size,
            chunk_hashes.items,
            fullFileHash,
        );
        defer fileobj.deinit();

        var manafest = try cache.createFile(manifest_name, .{});
        try fileobj.serialize(manafest.writer(), null);
        manafest.close();
    }

    /// Build the cache directory by chunking files and putting into cache
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

        pub fn next(self: *ChunkDir.Iterator) !?*File {
            if (self.current) |file| {
                file.deinit();
                self.allocator.destroy(file);
                self.current = null;
            }

            while (try self.inner_iterator.next()) |entry| {
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
