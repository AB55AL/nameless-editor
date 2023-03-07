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
    duplicates: u32,
};

pub fn notify(title: []const u8, message: []const u8, time: f32) void {
    for (ui.notifications.slice()) |*n| {
        if (std.mem.eql(u8, n.title, title) and std.mem.eql(u8, n.message, message)) {
            n.duplicates +|= 1;
            n.remaining_time = time;
            return;
        }
    }

    ui.notifications.append(.{
        .title = title,
        .message = message,
        .remaining_time = time,
        .duplicates = 0,
    }) catch return;
}

}

pub fn notifyWidget(allocator: std.mem.Allocator) !void {
    _ = allocator;
}
