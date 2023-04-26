const std = @import("std");

pub const Registers = @This();

data: std.StringArrayHashMapUnmanaged([]const u8) = .{},
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Registers {
    return .{ .allocator = allocator };
}

pub fn deinit(registers: *Registers) void {
    var iter = registers.data.iterator();
    while (iter.next()) |kv| {
        registers.allocator.free(kv.key_ptr.*);
        registers.allocator.free(kv.value_ptr.*);
    }

    registers.data.deinit(registers.allocator);
}

pub fn copyTo(registers: *Registers, register: []const u8, content: []const u8) !void {
    var value = registers.data.get(register);

    // Remove the old value to avoid problems with pointers
    if (value) |v| {
        var key = registers.data.getKey(register).?;
        _ = registers.data.orderedRemove(register);
        registers.allocator.free(v);
        registers.allocator.free(key);
    }

    var reg = try registers.allocator.alloc(u8, register.len);
    var string = try registers.allocator.alloc(u8, content.len);
    std.mem.copy(u8, reg, register);
    std.mem.copy(u8, string, content);

    try registers.data.put(registers.allocator, reg, string);
}

pub fn getFrom(registers: *Registers, register: []const u8) ?[]const u8 {
    return registers.registers.get(register);
}
