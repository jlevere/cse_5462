const std = @import("std");

const UDPSocket = struct {
    const Self = @This();
    socketfd: std.posix.socket_t,
    addr: std.net.Address,

    recvbuf: [65535]u8,

    pub fn init(addr: std.net.Address) !Self {
        return Self{
            .socketfd = try std.posix.socket(
                addr.any.family,
                std.posix.SOCK.DGRAM,
                std.posix.IPPROTO.UDP,
            ),
            .addr = addr,
            .recvbuf = undefined,
        };
    }

    pub fn deinit(self: Self) void {
        std.posix.close(self.socketfd);
    }

    pub fn bind(self: Self) !void {
        try std.posix.setsockopt(
            self.socketfd,
            std.posix.SOL.SOCKET,
            std.posix.SO.REUSEADDR,
            &std.mem.toBytes(@as(c_int, 1)),
        );
        try std.posix.bind(
            self.socketfd,
            &self.addr.any,
            self.addr.getOsSockLen(),
        );
        std.debug.print("[+] socket bound\n", .{});
    }

    pub fn listen(self: *Self) !void {
        std.debug.print("[+] listening on port {}\n", .{self.addr.getPort()});
        while (true) {
            var client_addr: std.net.Address = undefined;
            var client_addr_len: std.posix.socklen_t = self.addr.getOsSockLen();

            const bytes_recved = try std.posix.recvfrom(
                self.socketfd,
                &self.recvbuf,
                0,
                &client_addr.any,
                &client_addr_len,
            );

            if (bytes_recved > 0) {
                std.debug.print("[+] recv {} bytes from {} - '{s}'\n", .{ bytes_recved, client_addr, self.recvbuf[0..bytes_recved] });
            }

            const send_msg = "Welcome to CSE5462.";

            _ = try std.posix.sendto(
                self.socketfd,
                send_msg,
                0,
                &client_addr.any,
                client_addr_len,
            );

            std.debug.print("[+] {} connected\n", .{client_addr});
        }
    }
};

pub fn main() !void {
    var socket = try UDPSocket.init(try std.net.Address.resolveIp("127.0.0.1", 8001));
    defer socket.deinit();

    try socket.bind();

    try socket.listen();
}
