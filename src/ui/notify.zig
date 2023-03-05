const std = @import("std");
const print = std.debug.print;

const math = @import("math.zig");
const editor = @import("../globals.zig").editor;
const ui = @import("../globals.zig").ui;
const utils = @import("../utils.zig");

pub const Notify = struct {
    title: []const u8,
    message: []const u8,
    remaining_time: f32,
    duplicates: u8,
};

pub fn notify(title: []const u8, message: []const u8, time: f32) void {
    if (ui.notifications.len == ui.notifications.capacity()) return;

    ui.notifications.append(.{
        .title = title,
        .message = message,
        .remaining_time = time,
        .duplicates = 0,
    }) catch unreachable;
}

pub fn notifyWidget(allocator: std.mem.Allocator) !void {
    _ = allocator;
}
