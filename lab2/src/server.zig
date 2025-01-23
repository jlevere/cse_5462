const std = @import("std");
const UDPSocket = @import("sock.zig").UDPSocket;
const parse = @import("parser.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

fn msgHandler(
    client_addr: std.net.Address,
    recv_data: []const u8,
    resp_buf: []u8,
    alloc: std.mem.Allocator,
) UDPSocket.Error!?usize {
    _ = client_addr;
    _ = resp_buf;

    var map = try parse.parseMsg(alloc, recv_data);
    defer map.deinit();

    try parse.printData(map);

    return null;
}

test "msg handler test simple" {
    const test_cases = [_][]const u8{
        "version:1 cmd:send size:45KB",
        "version:2 cmd:recv msg:\" today2?\"  myName:DAVE",
    };

    const loopback = try std.net.Address.parseIp4("127.0.0.1", 0);
    var dummy_resp: [0]u8 = undefined;

    for (test_cases) |case| {
        _ = try msgHandler(
            loopback,
            case,
            &dummy_resp,
            std.testing.allocator,
        );
    }
}

pub fn main() !void {
    std.log.info("starting server", .{});
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa_impl.deinit() == .leak) {
        std.log.warn("gpa has leaked\n", .{});
    };
    const gpa = gpa_impl.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    if (std.os.argv.len != 3) {
        try stdout.print("Usage: {s} <ip> <port>\n", .{std.os.argv[0]});
        try bw.flush();
        std.posix.exit(1);
    }

    var socket = try UDPSocket.init();
    defer socket.deinit();

    try socket.bind(try std.net.Address.resolveIp(args[1], try std.fmt.parseInt(u16, args[2], 10)));

    try socket.listen(msgHandler, gpa);
}
