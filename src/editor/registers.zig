const std = @import("std");

const utils = @import("../utils.zig");

pub const Registers = @This();

data: std.StringArrayHashMapUnmanaged([]const u8) = .{},
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Registers {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Registers) void {
    var iter = self.data.iterator();
    while (iter.next()) |kv| {
        self.allocator.free(kv.key_ptr.*);
        self.allocator.free(kv.value_ptr.*);
    }

    self.data.deinit(self.allocator);
}

pub fn copyTo(self: *Registers, register: []const u8, content: []const u8) !void {
    var value = self.data.get(register);

    // Remove the old key/value to avoid problems with pointers
    if (value) |v| {
        var key = self.data.getKey(register).?;
        _ = self.data.orderedRemove(register);
        self.allocator.free(v);
        self.allocator.free(key);
    }

    var reg = try utils.newSlice(self.allocator, register);
    var string = try utils.newSlice(self.allocator, content);
    try self.data.put(self.allocator, reg, string);
}

pub fn getFrom(self: *Registers, register: []const u8) ?[]const u8 {
    return self.data.get(register);
}
