const std = @import("std");
const clap = @import("clap");
const UDPSocket = @import("sock.zig").UDPSocket;
const build_info = @import("build_info");
const FileRegistry = @import("file_registry.zig").FileRegistry;

pub const std_options: std.Options = .{
    .log_level = .debug,
};

comptime {
    _ = @import("bloom_filter.zig");
    _ = @import("file_registry.zig");
}

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

    var socket = try UDPSocket.init();
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
        const json_values = try std.json.parseFromSlice(
            std.json.Value,
            gpa,
            buf[0..recv_info.bytes_recv],
            .{ .allocate = .alloc_always },
        );
        defer json_values.deinit();

        switch (output_format) {
            .json => try printJson(stdout, json_values.value),
            .table => try printTable(stdout, json_values.value),
        }

        try stdout.print("\n", .{});
        try bw.flush();

        try stdout.print("updated regsitrystate: \n", .{});
        try bw.flush();

        try registry.registerFile(
            json_values.value.object.get("filename").?.string,
            json_values.value.object.get("fullFileHash").?.string,
            recv_info.sender,
        );

        try stdout.print("\x1b[2J\x1b[H", .{}); // clear terminal
        try bw.flush();

        try registry.printTable(stdout);
        try bw.flush();

        try stdout.print("\n", .{});
        try bw.flush();
    }
}

pub fn printJson(writer: anytype, value: std.json.Value) !void {
    try std.json.stringify(value, .{ .whitespace = .indent_1 }, writer);
}

/// Print simple json in a table format
pub fn printTable(writer: anytype, value: std.json.Value) !void {
    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        switch (entry.value_ptr.*) {
            .string => |str| try writer.print("{s:<20}{s:<}\n", .{ entry.key_ptr.*, str }),
            .integer => |int| try writer.print("{s:<20}{d:<}\n", .{ entry.key_ptr.*, int }),
            .float => |float| try writer.print("{s:<20}{:<}\n", .{ entry.key_ptr.*, float }),
            .bool => |b| try writer.print("{s:<20}{s:<}\n", .{ entry.key_ptr.*, if (b) "true" else "false" }),
            .null => try writer.print("{s:<20}{s:<}\n", .{ entry.key_ptr.*, "(null)" }),
            .array => {
                for (entry.value_ptr.array.items) |arr_item| {
                    try writer.print("{s:<20}{s:<}\n", .{ "", arr_item.string });
                }
            },
            .object => try writer.print("{s:<20}{s:<}\n", .{ entry.key_ptr.*, "(object)" }),
            else => unreachable,
        }
    }
}
