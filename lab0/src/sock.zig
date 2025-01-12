const std = @import("std");

const socket_log = std.log.scoped(.socket);

pub const UDPSocket = struct {
    const Self = @This();
    socketfd: std.posix.socket_t,
    addr: std.net.Address,

    recvbuf: [65535]u8,
    sendbuf: [65535]u8,

    pub const MessageHandler = fn (
        client_addr: std.net.Address,
        recv_data: []const u8,
        resp_buf: []u8,
    ) ?usize;

    pub fn init() !Self {
        return Self{
            .socketfd = try std.posix.socket(
                std.posix.AF.INET,
                std.posix.SOCK.DGRAM,
                std.posix.IPPROTO.UDP,
            ),
            .addr = undefined,
            .recvbuf = undefined,
            .sendbuf = undefined,
        };
    }

    pub fn deinit(self: Self) void {
        std.posix.close(self.socketfd);
    }

    pub fn send(self: *Self, to_address: std.net.Address, msg: []const u8) !void {
        self.addr = to_address;
        _ = try std.posix.sendto(
            self.socketfd,
            msg,
            0,
            &to_address.any,
            to_address.getOsSockLen(),
        );
    }

    pub fn recv(self: Self, buf: []u8) !usize {
        var client_addr: std.net.Address = undefined;
        var client_addr_len: std.posix.socklen_t = self.addr.getOsSockLen();

        const bytes_recved = try std.posix.recvfrom(
            self.socketfd,
            buf,
            0,
            &client_addr.any,
            &client_addr_len,
        );
        return bytes_recved;
    }

    pub fn bind(self: *Self, addr: std.net.Address) !void {
        self.addr = addr;

        try std.posix.setsockopt(
            self.socketfd,
            std.posix.SOL.SOCKET,
            std.posix.SO.REUSEADDR,
            &std.mem.toBytes(@as(c_int, 1)),
        );
        try std.posix.bind(
            self.socketfd,
            &addr.any,
            addr.getOsSockLen(),
        );

        socket_log.info("socket bound '{}'", .{addr});
    }

    pub fn listen(self: *Self, handler: MessageHandler) !void {
        socket_log.info("listening on port {}", .{self.addr.getPort()});
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

            if (bytes_recved == 0) {
                continue;
            }

            const recv_data = self.recvbuf[0..bytes_recved];

            socket_log.debug("connection from: '{}' recv: '{s}'", .{ client_addr, recv_data });

            if (handler(client_addr, recv_data, &self.sendbuf)) |resp_len| {
                _ = try std.posix.sendto(
                    self.socketfd,
                    self.sendbuf[0..resp_len],
                    0,
                    &client_addr.any,
                    client_addr_len,
                );

                socket_log.debug("sent to '{}' data: '{s}'", .{ client_addr, self.sendbuf[0..resp_len] });
            }
        }
    }
};
