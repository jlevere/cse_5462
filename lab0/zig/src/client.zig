const std = @import("std");
const UDPSocket = @import("sock.zig").UDPSocket;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var socket = try UDPSocket.init();
    defer socket.deinit();

    try socket.send(
        try std.net.Address.resolveIp("127.0.0.1", 8001),
        "Hello, World!",
    );

    var buf: [65535]u8 = undefined;

    const read = try socket.recv(&buf);

    try stdout.print("{s}\n", .{buf[0..read]});

    try bw.flush();
}
