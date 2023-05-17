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
    // The registers takes no ownership of the key string
    while (iter.next()) |kv|
        self.allocator.free(kv.value_ptr.*);

    self.data.deinit(self.allocator);
}

pub fn copyTo(self: *Registers, register: []const u8, content: []const u8) !void {
    const new_content = try self.allocator.dupe(u8, content);
    errdefer self.allocator.free(new_content);
    var gop = try self.data.getOrPut(self.allocator, register);

    if (gop.found_existing) self.allocator.free(gop.value_ptr.*);
    gop.value_ptr.* = new_content;
}

pub fn getFrom(self: *Registers, register: []const u8) ?[]const u8 {
    return self.data.get(register);
}
