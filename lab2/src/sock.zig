const std = @import("std");

const socket_log = std.log.scoped(.socket);

pub const UDPSocket = struct {
    const Self = @This();
    socketfd: std.posix.socket_t,
    addr: std.net.Address,

    recvbuf: [65535]u8,
    sendbuf: [65535]u8,

    pub const Error = error{OutOfMemory};

    pub const MessageHandler = fn (
        client_addr: std.net.Address,
        recv_data: []const u8,
        resp_buf: []u8,
        alloc: std.mem.Allocator,
    ) Error!?usize;

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

        if (addr.any.family != std.posix.AF.INET) {
            return error.IPv4OnlySupported;
        }

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

        if (isIpv4Multicast(addr)) {
            socket_log.info("Addr is multicast, adding multicast sockopts", .{});

            const ip_mreq = extern struct {
                imr_multiaddr: u32,
                imr_address: u32,
                imr_ifindex: u32,
            };

            const mreq = ip_mreq{
                .imr_multiaddr = addr.in.sa.addr,
                .imr_address = 0,
                .imr_ifindex = 0,
            };

            try std.posix.setsockopt(
                self.socketfd,
                std.posix.SOL.SOCKET,
                std.os.linux.IP.ADD_MEMBERSHIP,
                &std.mem.toBytes(&mreq),
            );
        }

        // Validate we are bound to the right port
        var bound_addr: std.net.Address = undefined;
        var bound_addr_len: std.posix.socklen_t = self.addr.getOsSockLen();

        try std.posix.getsockname(self.socketfd, &bound_addr.any, &bound_addr_len);

        socket_log.info("Socket bound to '{}'", .{bound_addr.getPort()});
    }

    pub fn listen(self: *Self, handler: MessageHandler, alloc: std.mem.Allocator) !void {
        socket_log.info("Listening on port '{}'", .{self.addr.getPort()});
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

            socket_log.debug("msg from: '{}' recv: '{s}'", .{
                client_addr,
                recv_data,
            });

            if (try handler(
                client_addr,
                recv_data,
                &self.sendbuf,
                alloc,
            )) |resp_len| {
                _ = try std.posix.sendto(
                    self.socketfd,
                    self.sendbuf[0..resp_len],
                    0,
                    &client_addr.any,
                    client_addr_len,
                );

                socket_log.debug("sent to '{}' data: '{s}'", .{
                    client_addr,
                    self.sendbuf[0..resp_len],
                });
            }
        }
    }
};

pub fn isIpv4Multicast(addr: std.net.Address) bool {
    const octets = std.mem.asBytes(&addr.in.sa.addr);
    return octets[0] >= 224 and octets[0] <= 239;
}

test "ipv4 multicast check test" {
    const loopback = try std.net.Address.parseIp4("127.0.0.1", 0);
    const valid_multicast = try std.net.Address.parseIp4("224.0.0.1", 0);
    const invalid_multicast = try std.net.Address.parseIp4("240.0.0.1", 0);

    // Loopback should not be multicast
    try std.testing.expect(!isIpv4Multicast(loopback));

    // Valid multicast
    try std.testing.expect(isIpv4Multicast(valid_multicast));

    try std.testing.expect(!isIpv4Multicast(invalid_multicast));
}
