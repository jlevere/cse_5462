const std = @import("std");

const socket_log = std.log.scoped(.socket);

/// A UDP socket supporting direct and multicast IPv4
pub const UDPSocket = struct {
    const Self = @This();

    /// Underlying OS socket file descriptor
    socketfd: std.posix.socket_t,

    /// Address the socket is bound to
    bound_addr: std.net.Address,

    /// UDP socket operation errors
    pub const Error = error{
        IPv4OnlySupported,
        SocketOptionError,
        BindFailed,
    };

    /// Creates a new UDP socket
    /// Caller must call `deinit()` to clean up resources
    pub fn init(block: bool) !Self {
        return Self{
            .socketfd = try std.posix.socket(
                std.posix.AF.INET,
                if (!block) std.posix.SOCK.DGRAM | std.posix.SOCK.NONBLOCK else std.posix.SOCK.DGRAM,
                std.posix.IPPROTO.UDP,
            ),
            .bound_addr = undefined,
        };
    }

    pub fn deinit(self: Self) void {
        std.posix.close(self.socketfd);
    }

    /// Sends data to the specified destination address
    /// Arguments:
    /// - `dest`: Target address for the datagram
    /// - `data`: Payload to send (max 65535 bytes)
    ///
    /// Returns error if underlying sendto() call fails
    pub fn sendTo(self: *Self, dest: std.net.Address, data: []const u8) !void {
        const rc = try std.posix.sendto(
            self.socketfd,
            data,
            0,
            &dest.any,
            dest.getOsSockLen(),
        );

        socket_log.debug("Send dest: {} msg: {s}", .{ dest, data });

        if (rc != data.len) {
            socket_log.err("Partial send: {d} of {d} bytes", .{ rc, data.len });
        }
    }

    /// Receives data from the socket
    /// Arguments:
    /// - `buf`: Buffer to store received data (max size: 65535)
    ///
    /// Returns:
    ///   - sender: Source address of received data
    ///   - bytes_recv: Number of bytes received
    ///
    pub fn recvFrom(self: Self, buf: []u8) !struct {
        sender: std.net.Address,
        bytes_recv: usize,
    } {
        var sender_addr: std.net.Address = undefined;
        var sender_addr_len: std.posix.socklen_t = self.bound_addr.getOsSockLen();

        const bytes_recved = try std.posix.recvfrom(
            self.socketfd,
            buf,
            0,
            &sender_addr.any,
            &sender_addr_len,
        );

        socket_log.debug("From {} got: {s}", .{ sender_addr, buf[0..bytes_recved] });

        return .{
            .sender = sender_addr,
            .bytes_recv = bytes_recved,
        };
    }

    /// Binds the socket to a specific address
    ///
    /// Arguments:
    /// - `addr`: Local address to bind to (must be IPv4)
    ///
    /// Sets SO_REUSEADDR option automatically
    ///
    /// Handles multicast group joining if address is multicast
    pub fn bind(self: *Self, addr: std.net.Address) !void {
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
            socket_log.info("Joining IPv4 multicast group {any}", .{addr});

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
        var bound_addr_len: std.posix.socklen_t = addr.getOsSockLen();
        try std.posix.getsockname(self.socketfd, &bound_addr.any, &bound_addr_len);
        self.bound_addr = bound_addr;

        socket_log.info("Bound to {any}", .{bound_addr});
    }
};

/// Checks IPv4 address in multicast range (224.0.0.0/4)
/// Returns true if first octet between 224-239, inclusive
pub fn isIpv4Multicast(addr: std.net.Address) bool {
    const octets = std.mem.asBytes(&addr.in.sa.addr);
    return octets[0] >= 224 and octets[0] <= 239;
}

test "ipv4 multicast check test" {
    const loopback = try std.net.Address.parseIp4("127.0.0.1", 0);
    const valid_multicast = try std.net.Address.parseIp4("224.0.0.1", 0);
    const invalid_multicast = try std.net.Address.parseIp4("240.0.0.1", 0);

    try std.testing.expect(!isIpv4Multicast(loopback));
    try std.testing.expect(isIpv4Multicast(valid_multicast));
    try std.testing.expect(!isIpv4Multicast(invalid_multicast));
}

test "Send/Receive basic messages" {
    var receiver = try UDPSocket.init();
    defer receiver.deinit();
    try receiver.bind(try std.net.Address.parseIp4("127.0.0.1", 0));

    var sender = try UDPSocket.init();
    defer sender.deinit();

    const test_data = "hello there fren :)";
    var recv_buf: [1024]u8 = undefined;

    try sender.sendTo(receiver.bound_addr, test_data);

    const result = try receiver.recvFrom(&recv_buf);
    try std.testing.expectEqualStrings(
        test_data,
        recv_buf[0..result.bytes_recv],
    );
}
