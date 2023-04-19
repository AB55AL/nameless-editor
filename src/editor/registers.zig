const std = @import("std");

const globals = @import("../globals.zig");
const editor = globals.editor;
const internal = globals.internal;

pub fn deinit() void {
    var iter = editor.registers.iterator();
    while (iter.next()) |kv| {
        internal.allocator.free(kv.key_ptr.*);
        internal.allocator.free(kv.value_ptr.*);
    }

    editor.registers.deinit(internal.allocator);
}

pub fn copyTo(register: []const u8, content: []const u8) !void {
    var value = editor.registers.get(register);

    if (value) |v| {
        var key = editor.registers.getKey(register).?;
        _ = editor.registers.remove(register);
        internal.allocator.free(v);
        internal.allocator.free(key);
    }

    var reg = try internal.allocator.alloc(u8, register.len);
    var string = try internal.allocator.alloc(u8, content.len);
    std.mem.copy(u8, reg, register);
    std.mem.copy(u8, string, content);
    try editor.registers.put(internal.allocator, reg, string);
}

pub fn getFrom(register: []const u8) ?[]const u8 {
    return editor.registers.get(register);
}
