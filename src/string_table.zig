const std = @import("std");
const utils = @import("utils.zig");

pub fn StringTable(comptime T: type) type {
    return struct {
        const Self = @This();

        const HashContext = struct {
            pub fn hash(self: HashContext, keys: [2][]const u8) u64 {
                _ = self;
                var wh = std.hash.Wyhash.init(0);

                wh.update(keys[0]);
                wh.update(keys[1]);

                return wh.final();
            }

            pub fn eql(self: HashContext, a: [2][]const u8, b: [2][]const u8) bool {
                _ = self;
                for (a, b) |a_array, b_array| if (!std.mem.eql(u8, a_array, b_array)) return false;
                return true;
            }
        };

        const HashMap = std.HashMapUnmanaged([2][]const u8, T, HashContext, std.hash_map.default_max_load_percentage);
        data: HashMap = .{},

        pub fn get(self: *Self, row: []const u8, col: []const u8) ?T {
            return self.data.get(.{ row, col });
        }

        pub fn put(self: *Self, allocator: std.mem.Allocator, row: []const u8, col: []const u8, value: T) !void {
            try self.data.put(allocator, .{ row, col }, value);
        }
    };
}

test "StringTable()" {
    const allocator = std.testing.allocator;
    var table = StringTable(u32){};
    defer table.data.deinit(allocator);

    try table.put(allocator, "A", "a", 0);
    try table.put(allocator, "A", "b", 1);
    try table.put(allocator, "A", "c", 2);
    try table.put(allocator, "A", "c", 3);

    try table.put(allocator, "B", "a", 100);
    try table.put(allocator, "B", "b", 200);
    try table.put(allocator, "B", "c", 300);
    try table.put(allocator, "B", "c", 300);

    try std.testing.expect(table.get("A", "a") == @as(u32, 0));
    try std.testing.expect(table.get("A", "b") == @as(u32, 1));
    try std.testing.expect(table.get("A", "c") == @as(u32, 3));
}
