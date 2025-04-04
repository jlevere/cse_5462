const std = @import("std");
const clap = @import("clap");
const UDPSocket = @import("sock.zig").UDPSocket;
const build_info = @import("build_info");
const FileRegistry = @import("file_registry.zig").FileRegistry;

comptime {
    _ = @import("bloom_filter.zig");
    _ = @import("file_chunking.zig");
    _ = @import("file_registry.zig");
}

pub const std_options: std.Options = .{
    .log_level = .info,
};

const log = std.log.scoped(.server);

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa_impl.deinit() == .leak) {
        std.log.warn("gpa has leaked\n", .{});
    };
    const gpa = gpa_impl.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help               Display this help and exit
        \\--version                Display the current version
        \\-i, --ip <str>           IP address to bind to (default: 0.0.0.0)
        \\-p, --port <u16>         Port number to bind to (required)
        \\-f, --format <str>       Output format: json, table (default: table)
        \\<str>...                 Positional arguments [PORT]
        \\
    );

    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return;
    };
    defer res.deinit();

    if (res.args.help != 0) return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    if (res.args.version != 0) {
        std.debug.print("{s}\n", .{build_info.version});
        return;
    }

    const port = res.args.port orelse blk: {
        if (res.positionals[0].len < 1) {
            std.log.err("Port number is required\n", .{});
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        }
        const port_str = res.positionals[0][0];
        break :blk std.fmt.parseInt(u16, port_str, 10) catch |err| {
            std.log.err("Invalid port '{s}': {s}\n", .{ port_str, @errorName(err) });
            return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        };
    };

    const ip = res.args.ip orelse "0.0.0.0";

    const format = res.args.format orelse "table";
    const output_format = std.meta.stringToEnum(enum { json, table }, format) orelse {
        std.log.err("Invalid format '{s}'. Must be 'json' or 'table'\n", .{format});
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    };

    var socket = try UDPSocket.init(true);
    defer socket.deinit();
    try socket.bind(try std.net.Address.resolveIp(ip, port));

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var registry = try FileRegistry.init(gpa);
    defer registry.deinit();

    while (true) {
        const buf = try gpa.alloc(u8, 65535);
        defer gpa.free(buf);

        const recv_info = try socket.recvFrom(buf);
        const json_values = std.json.parseFromSlice(
            std.json.Value,
            gpa,
            buf[0..recv_info.bytes_recv],
            .{ .allocate = .alloc_always },
        ) catch |err| {
            log.err("unable to parse json with error: {any}\nThe message in question: \n{s}\n", .{ err, buf[0..recv_info.bytes_recv] });
            continue;
        };
        defer json_values.deinit();

        const Commands = enum { upload, query, queryResponse, notfound };
        const request_type = (json_values.value.object.get("requestType") orelse std.json.Value{ .string = "notfound" }).string;
        const case = std.meta.stringToEnum(Commands, request_type) orelse Commands.notfound;
        switch (case) {
            .upload => {
                try stdout.print("\n", .{});
                try stdout.print("updated regsitrystate: \n", .{});

                try registry.registerFile(
                    json_values.value.object.get("filename").?.string,
                    json_values.value.object.get("fileSize").?.integer,
                    json_values.value.object.get("fullFileHash").?.string,

                    recv_info.sender,
                );

                try stdout.print("\x1b[2J\x1b[H\x1b[3J", .{}); // clear terminal
                try bw.flush();

                switch (output_format) {
                    .json => try registry.serialize(stdout),
                    .table => try registry.printTable(stdout),
                }

                try stdout.print("\n", .{});
            },
            .query => {
                try stdout.print("got a query from {}\n", .{recv_info.sender});

                var sendbuf = std.ArrayList(u8).init(gpa);
                defer sendbuf.deinit();

                try registry.queryResponse(sendbuf.writer());

                try socket.sendTo(recv_info.sender, sendbuf.items);
            },
            .queryResponse => {
                try stdout.print("got a query response\n", .{});
            },
            .notfound => {
                try stdout.print("got malformed json: ", .{});
                try std.json.stringify(
                    json_values.value,
                    .{ .whitespace = .indent_tab },
                    stdout,
                );

                log.debug("got malformed json, does not contain valid request Type", .{});
            },
        }
        try bw.flush();
    }
}
