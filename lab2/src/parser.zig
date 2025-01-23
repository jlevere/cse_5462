const std = @import("std");

const p_log = std.log.scoped(.parser);

const MAX_LENGTH = 20;

pub fn parseMsg(alloc: std.mem.Allocator, input: []const u8) !std.StringArrayHashMap([]const u8) {
    var map = std.StringArrayHashMap([]const u8).init(alloc);
    errdefer map.deinit();

    var pos: usize = 0;
    while (pos < input.len) {
        const colon_pos = std.mem.indexOfScalarPos(u8, input, pos, ':') orelse break;

        var key = std.mem.trimLeft(u8, input[pos..colon_pos], &std.ascii.whitespace);

        const next_key_pos = std.mem.indexOfScalarPos(u8, input, colon_pos + 1, ':') orelse input.len;

        var value_end = next_key_pos;
        if (std.mem.lastIndexOfScalar(u8, input[colon_pos + 1 .. next_key_pos], ' ')) |last_space| {
            value_end = colon_pos + 1 + last_space;
        }

        const value = std.mem.trim(u8, input[colon_pos + 1 .. value_end], &std.ascii.whitespace);

        pos = value_end;
        if (key.len == 0) {
            break;
        }

        const cut_key = if (key.len > MAX_LENGTH) key[0..20] else key;
        const cut_value = if (value.len > MAX_LENGTH) value[0..20] else value;

        try map.put(cut_key, cut_value);
    }
    return map;
}

pub fn printData(map: std.StringArrayHashMap([]const u8)) !void {
    var iter = map.iterator();
    while (iter.next()) |entry| {
        std.debug.print("{s:<20}{s:<20}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    std.debug.print("\n", .{});
}

test "parseMsg with valid inputs" {
    const allocator = std.testing.allocator;

    const test_cases = [_][]const u8{
        "version:1 cmd:send msg:\" today1?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:2 cmd:recv msg:\" today2?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:3 cmd:send msg:\" today3?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:4 cmd:recv msg:\" today4?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:5 cmd:send msg:\" today5\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:6 cmd:recv msg:\" today6?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:7 cmd:send msg:\" today7?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:8 cmd:send msg:\" today8?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:9 cmd:send msg:\" today9?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:10 cmd:send msg:\" today10?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
        "version:11 cmd:send msg:\" today11?\" time:1228 date:12-1-1 destination:1001 location:20 TTL:300 myName:DAVE",
    };

    for (test_cases) |input| {
        var map = try parseMsg(allocator, input);
        defer map.deinit();

        try std.testing.expect(map.contains("version"));
        try std.testing.expect(map.contains("cmd"));
        try std.testing.expect(map.contains("time"));
        try std.testing.expect(map.contains("date"));
        try std.testing.expect(map.contains("destination"));
        try std.testing.expect(map.contains("location"));
        try std.testing.expect(map.contains("TTL"));
        try std.testing.expect(map.contains("myName"));

        const msg = map.get("msg").?;
        try std.testing.expect(msg.len <= MAX_LENGTH);

        const TTL = map.get("TTL").?;
        try std.testing.expectEqualStrings("300", TTL);
    }
}

test "parseMsg with invalid inputs" {
    const allocator = std.testing.allocator;

    const test_cases = [_][]const u8{
        "invalid_key_without_value:",
        "key_without_colon value",
        "key:value key_without_value",
    };

    for (test_cases) |input| {
        var map = try parseMsg(allocator, input);
        defer map.deinit();

        // Ensure invalid entries are skipped
        try std.testing.expect(map.count() == 0 or map.count() == 1);
    }
}
