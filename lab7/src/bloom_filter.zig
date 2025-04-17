const std = @import("std");
const math = std.math;
const debug = std.debug;
const assert = std.debug.assert;
const testing = std.testing;

/// Very simple bloomfilter, derived from
/// historic zig std library
/// https://github.com/ziglang/std-lib-orphanage/blob/master/std/bloom_filter.zig
///
/// To calculate the optimal settings for bloomfilter for application
/// can use this website https://hur.st/bloomfilter/
///
/// TL:DR the bigger it is, the less hashes needed, and faster
///
///
///
/// Handy functions to setup  filter:
///
/// // Configuration for 100,000 items with 1% false positives
///
/// const expected_items = 100_000;
/// const false_pos_rate = 0.01;
///
/// const n_bits = std.math.ceilPowerOfTwo(
///     usize,
///     @as(
///         usize,
///         @intFromFloat(-(@as(f64, @floatFromInt(expected_items)) * @log(false_pos_rate) / (std.math.ln2 * std.math.ln2))),
///     ),
/// ) catch unreachable;
/// const K = @max(
///     1,
///     @as(
///         usize,
///         @intFromFloat((@as(f64, @floatFromInt(n_bits)) / expected_items) * std.math.ln2),
///     ),
/// );
///
/// const bf = BloomFilter(n_bits, K, WyHash);
pub fn BloomFilter(
    /// Size of bloom filter in bits, must be a power of two
    comptime n_bits: usize,
    /// Number of hash functions to use (bits to set per item)
    comptime K: usize,
    /// Hash function that takes a hash index and item, returns u64
    comptime hash: fn (usize, []const u8) u64,
) type {
    std.debug.assert(n_bits > 0);
    std.debug.assert(math.isPowerOfTwo(n_bits));
    std.debug.assert(K > 0);

    const n_bytes = n_bits / 8;

    return struct {
        const Self = @This();

        data: [n_bytes]u8 = [_]u8{0} ** n_bytes,

        /// Reset the Bloom filter to empty state
        pub fn reset(self: *Self) void {
            @memset(&self.data, 0);
        }

        /// Add an item to the Bloom filter
        pub fn add(self: *Self, item: []const u8) void {
            comptime var i: usize = 0;
            inline while (i < K) : (i += 1) {
                const h = hash(i, item);
                const index = @as(usize, h) & (n_bits - 1);
                const byte = index >> 3;
                const bit = @as(u3, @intCast(index & 0x7));
                self.data[byte] |= @as(u8, 1) << bit;
            }
        }

        /// Check if an item might be in the Bloom filter
        pub fn contains(self: *const Self, item: []const u8) bool {
            comptime var i: usize = 0;
            inline while (i < K) : (i += 1) {
                const h = hash(i, item);
                const index = @as(usize, h) & (n_bits - 1);
                const byte = index >> 3;
                const bit = @as(u3, @intCast(index & 0x7));
                if ((self.data[byte] & (@as(u8, 1) << bit) == 0)) return false;
            }
            return true;
        }
    };
}

/// Helper function to create a BloomFilter with optimal parameters based on
/// the expected number of items and desired false positive rate.
/// Uses WyHash as the hash function.
///
/// expected_items: Number of items expected to be stored in the filter
/// false_pos_rate: Desired false positive rate (between 0 and 1)
///
/// Returns a configured BloomFilter or an error if parameters are invalid
pub fn WyBloomFilter(expected_items: usize, false_pos_rate: f64) !type {
    if (expected_items == 0) {
        return error.InvalidItemCount;
    }
    if (false_pos_rate <= 0 or false_pos_rate >= 1) {
        return error.InvalidFalsePositiveRate;
    }

    // Calculate optimal size (in bits)
    const bits_needed = @as(usize, @intFromFloat(-(@as(f64, @floatFromInt(expected_items)) * @log(false_pos_rate) / (std.math.ln2 * std.math.ln2))));

    // Round up to next power of two
    const n_bits = try std.math.ceilPowerOfTwo(usize, bits_needed);

    // Calculate optimal number of hash functions
    const K = @max(1, @as(usize, @intFromFloat((@as(f64, @floatFromInt(n_bits)) / expected_items) * std.math.ln2)));

    return BloomFilter(n_bits, K, wyhash);
}

/// Very fast hash for 64bit arch with small keys
/// https://github.com/wangyi-fudan/wyhash
pub fn wyhash(ki: usize, input: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(@intCast(ki));
    hasher.update(input);
    return hasher.final();
}

test "BloomFilter basic usage" {
    var bf = BloomFilter(1024, 3, wyhash){};

    try std.testing.expect(!bf.contains("foo"));
    bf.add("foo");
    try std.testing.expect(bf.contains("foo"));

    bf.reset();
    try std.testing.expect(!bf.contains("foo"));
}

test "BloomFilter false positives" {
    var bf = BloomFilter(8192, 7, wyhash){};

    const items = [_][]const u8{ "hithere", "fren", ":3", "whatdo", "yearg", "sharg...." };
    for (items) |item| bf.add(item);

    for (items) |item|
        try std.testing.expect(bf.contains(item));

    try std.testing.expect(!bf.contains("fig"));
}

fn testOne(context: void, input: []const u8) anyerror!void {
    _ = context;

    var bf = BloomFilter(8192, 7, wyhash){};
    bf.add(input);

    try std.testing.expect(bf.contains(input));

    bf.reset();

    bf.add(input);
    try std.testing.expect(bf.contains(input));
}

test "BloomFilter fuzz" {
    try std.testing.fuzz({}, testOne, .{});
}
