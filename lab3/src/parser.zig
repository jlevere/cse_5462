const std = @import("std");

const json = std.json;
const p_log = std.log.scoped(.parser);

///
/// Backtracking parser for input message format.  The message format consists of keys and values
/// which are ':' seperted and each pair is sperated from the next by whitespace.
///
/// Note: this parser makes some harsh assumptions including that there is no space between the end of the
/// key and the colon. Among others.
///
/// On invalid format, parser will skip input.
///
pub fn parseMsg(alloc: std.mem.Allocator, input: []const u8) !std.StringArrayHashMap([]const u8) {
    var map = std.StringArrayHashMap([]const u8).init(alloc);
    errdefer map.deinit();

    var pos: usize = 0;
    while (pos < input.len) {
        const colon_pos = std.mem.indexOfScalarPos(u8, input, pos, ':') orelse break;

        const key = std.mem.trimLeft(u8, input[pos..colon_pos], &std.ascii.whitespace);

        const next_colon_pos = std.mem.indexOfScalarPos(u8, input, colon_pos + 1, ':') orelse input.len;

        var value_end = next_colon_pos;
        if (std.mem.lastIndexOfScalar(u8, input[colon_pos + 1 .. next_colon_pos], ' ')) |last_space| {
            value_end = colon_pos + 1 + last_space;
        }

        // This means we are at the end and there is no other key.
        // So we should not trim back for the next key like we usually do.
        if (next_colon_pos == input.len) {
            value_end = input.len;
        }

        const value = std.mem.trim(u8, input[colon_pos + 1 .. value_end], &std.ascii.whitespace);

        pos = value_end;
        if (key.len == 0 or value.len == 0) {
            break;
        }

        try map.put(key, value);
    }
    return map;
}

pub fn printData(map: std.StringArrayHashMap([]const u8), writer: std.fs.File.Writer) !void {
    var iter = map.iterator();
    while (iter.next()) |entry| {
        try writer.print("{s:<20}{s:<20}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    try writer.print("\n", .{});
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

        try std.testing.expectEqualStrings("300", map.get("TTL").?);
        try std.testing.expectEqualStrings("DAVE", map.get("myName").?);
        try std.testing.expectEqualStrings("20", map.get("location").?);
        try std.testing.expectEqualStrings("1001", map.get("destination").?);
        try std.testing.expectEqualStrings("12-1-1", map.get("date").?);
    }
}

test "parseMsg with multi word final value - problematic case" {
    const allocator = std.testing.allocator;
    const input = "myName:\"not dave\"";

    var map = try parseMsg(allocator, input);
    defer map.deinit();

    try std.testing.expectEqualStrings("\"not dave\"", map.get("myName").?);
}

test "parseMsg with duplicate keys" {
    const allocator = std.testing.allocator;
    const input = "myName:\"not dave\" myName:\"not dave\"";

    var map = try parseMsg(allocator, input);
    defer map.deinit();

    try std.testing.expectEqualStrings("\"not dave\"", map.get("myName").?);
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

        try std.testing.expect(map.count() == 0 or map.count() == 1);
    }
}

///
/// Takes a string containing "message" format of keys and values and returns
/// them in json format. Caller owns result.
///
pub fn jsonify_msg(
    alloc: std.mem.Allocator,
    input: []const u8,
) ![]const u8 {
    var map = try parseMsg(alloc, input);
    defer map.deinit();

    var json_buffer = std.ArrayList(u8).init(alloc);
    const writer = json_buffer.writer();
    var jws = json.writeStream(writer, .{});

    try jws.beginObject();
    var it = map.iterator();
    while (it.next()) |kv| {
        try jws.objectField(kv.key_ptr.*);
        try jws.write(kv.value_ptr.*);
    }
    try jws.endObject();

    return json_buffer.toOwnedSlice();
}

test "jsonify_msg - file metadata example" {
    const allocator = std.testing.allocator;

    const input =
        \\File_Name:"Presentation3.key" File_Size:2.5MB File_Type:"Presentation" Date_Created:"2024-08-02" Description:"Design review presentation"
    ;

    const result = try jsonify_msg(allocator, input);
    defer allocator.free(result);

    const expected =
        \\{"File_Name":"\"Presentation3.key\"","File_Size":"2.5MB","File_Type":"\"Presentation\"","Date_Created":"\"2024-08-02\"","Description":"\"Design review presentation\""}
    ;
    try std.testing.expectEqualStrings(expected, result);
}

test "jsonify_msg - mixed quoted and unquoted values" {
    const allocator = std.testing.allocator;

    const input =
        \\name:"test.txt" size:500KB type:document created:"2024-01-01"
    ;

    const result = try jsonify_msg(allocator, input);
    defer allocator.free(result);

    const expected =
        \\{"name":"\"test.txt\"","size":"500KB","type":"document","created":"\"2024-01-01\""}
    ;
    try std.testing.expectEqualStrings(expected, result);
}

test "jsonify_msg - empty input" {
    const allocator = std.testing.allocator;
    const result = try jsonify_msg(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("{}", result);
}

test "jsonify_msg - single pair" {
    const allocator = std.testing.allocator;
    const input = "key:value";

    const result = try jsonify_msg(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("{\"key\":\"value\"}", result);
}

test "jsonify_msg - whitespace handling" {
    const allocator = std.testing.allocator;

    const input =
        \\   key1:"value1"     key2:value2   key3:"value3"   
    ;

    const result = try jsonify_msg(allocator, input);
    defer allocator.free(result);

    const expected =
        \\{"key1":"\"value1\"","key2":"value2","key3":"\"value3\""}
    ;
    try std.testing.expectEqualStrings(expected, result);
}
