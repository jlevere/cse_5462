const std = @import("std");
const clap = @import("clap");
const UDPSocket = @import("sock.zig").UDPSocket;
const parse = @import("parser.zig");
const build_info = @import("build_info");

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa_impl.deinit() == .leak) {
        std.log.warn("gpa has leaked\n", .{});
    };
    const gpa = gpa_impl.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help       Display this help and exit.
        \\--version        Display the current version
        \\--ip <str>       IP address to bind (optional)
        \\--port <u16>     Port number to bind (optional)
        \\<str>...     Positional arguments [IP] [PORT]
        \\
    );

    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.version != 0) {
        std.debug.print("{s}\n", .{build_info.version});
        return;
    }

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    const ip = res.args.ip orelse blk: {
        if (res.positionals[0].len < 1) {
            std.log.err("IP address required", .{});
            std.log.err("Use --ip or provide as first argument", .{});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        }
        break :blk res.positionals[0][0];
    };

    const port = res.args.port orelse blk: {
        if (res.positionals[0].len < 2) {
            std.log.err("Port number required", .{});
            std.log.err("Use --port or provide as second argument", .{});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        }
        const port_str = res.positionals[0][1];
        break :blk std.fmt.parseInt(u16, port_str, 10) catch |err| {
            std.log.err("Invalid port '{s}': {s}", .{ port_str, @errorName(err) });
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        };
    };

    var socket = try UDPSocket.init();
    defer socket.deinit();
    try socket.bind(try std.net.Address.resolveIp(ip, port));

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    while (true) {
        const buf = try gpa.alloc(u8, 65535);
        defer gpa.free(buf);

        const recv_info = try socket.recvFrom(buf);

        const json_values = try std.json.parseFromSlice(
            std.json.Value,
            gpa,
            buf[0..recv_info.bytes_recv],
            .{ .allocate = .alloc_always },
        );
        defer json_values.deinit();

        var iter = json_values.value.object.iterator();
        while (iter.next()) |entry| {
            try stdout.print("{s:<20}{s:<}\n", .{ entry.key_ptr.*, entry.value_ptr.string });
        }
        try bw.flush();
    }
}
