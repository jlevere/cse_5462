const std = @import("std");
const UDPSocket = @import("sock.zig").UDPSocket;

pub fn main() !void {
    var socket = try UDPSocket.init();
    defer socket.deinit();

    try socket.bind(try std.net.Address.resolveIp("127.0.0.1", 8001));

    try socket.listen();
}
