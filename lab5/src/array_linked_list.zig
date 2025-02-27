const std = @import("std");

/// Arraylist backed linked list for better memory locality
pub fn ArrayLinkedList(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Node inside the linked list wrapping the actual data.
        const Node = struct {
            data: T,
            next: ?usize,
            prev: ?usize,
        };

        nodes: std.ArrayList(Node),
        free_head: ?usize = null,
        first: ?usize = null,
        last: ?usize = null,
        len: usize = 0,

        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .nodes = std.ArrayList(Node).init(alloc),
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            // for (self.nodes.items) |node| {
            //     self.allocator.free(node);
            // }
            self.nodes.deinit();
        }

        pub fn append(self: *Self, data: T) !void {
            const new_node = try self.createNode(data);
            if (self.last) |last| {
                self.nodes.items[last].next = new_node;
                self.nodes.items[new_node].prev = last;
            } else {
                self.first = new_node;
            }

            self.last = new_node;
            self.len += 1;
        }

        /// Remove a node by index
        pub fn remove(self: *Self, node_idx: usize) void {
            const node = self.nodes.items[node_idx];

            if (node.prev) |prev| {
                self.nodes.items[prev].next = node.next;
            } else {
                self.first = node.next;
            }

            if (node.next) |next| {
                self.nodes.items[next].prev = node.prev;
            } else {
                self.last = node.prev;
            }

            self.recycleNode(node_idx);
            self.len -= 1;
        }

        /// Internal: Allocate a new empty node and return its index
        fn addNode(self: *Self) !usize {
            try self.nodes.append(undefined);
            return self.nodes.items.len - 1;
        }

        fn recycleNode(self: *Self, idx: usize) void {
            self.nodes.items[idx].next = self.free_head;
            self.nodes.items[idx].prev = null;
            self.free_head = idx;
        }

        /// Internal: Make a new node with data
        fn createNode(self: *Self, data: T) !usize {
            const idx = if (self.free_head) |free| blk: {
                self.free_head = self.nodes.items[free].next;
                break :blk free;
            } else try self.addNode();

            self.nodes.items[idx] = .{
                .data = data,
                .prev = null,
                .next = null,
            };

            return idx;
        }

        pub const Iterator = struct {
            list: *const Self,
            current: ?usize,

            pub fn next(it: *Iterator) ?*const Node {
                const idx = it.current orelse return null;
                it.current = it.list.nodes.items[idx].next;
                return &it.list.nodes.items[idx];
            }
        };

        pub fn iterator(self: *const Self) Iterator {
            return .{
                .list = self,
                .current = self.first,
            };
        }
    };
}

test "array-backed linked list basic append" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var list = ArrayLinkedList(u32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);

    var it = list.iterator();
    try testing.expectEqual(@as(u32, 1), it.next().?.data);
    try testing.expectEqual(@as(u32, 2), it.next().?.data);
    try testing.expect(it.next() == null);
}

test "array-backed linked list  complex append" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const Person = struct {
        name: []const u8,
        friends: [][]const u8,
    };

    var list = ArrayLinkedList(Person).init(allocator);
    defer list.deinit();

    var friends = std.ArrayList([]const u8).init(testing.allocator);
    defer friends.deinit();

    try friends.append("hi fren");

    try list.append(.{ .name = "my name", .friends = friends.items });

    var it = list.iterator();
    try testing.expectEqualStrings("my name", it.next().?.data.name);
    try testing.expect(it.next() == null);
}
