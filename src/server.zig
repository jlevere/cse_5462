const std = @import("std");
const UDPSocket = @import("sock.zig").UDPSocket;

fn msgHandler(
    client_addr: std.net.Address,
    recv_data: []const u8,
    resp_buf: []u8,
) ?usize {
    _ = client_addr;
    _ = recv_data;

    const resp = "Welcome to CSE5462.";
    @memcpy(resp_buf[0..resp.len], resp);
    return resp.len;
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

    try socket.listen(msgHandler);
}
