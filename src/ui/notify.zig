const std = @import("std");
const print = std.debug.print;

const gui = @import("gui");

const math = @import("math.zig");
const editor = @import("../globals.zig").editor;
const ui = @import("../globals.zig").ui;
const utils = @import("../utils.zig");

pub const Notify = struct {
    title: []const u8,
    message: []const u8,
    /// Remaining time in seconds
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

pub fn displayNotifications(notifications: []Notify) !void {
    _ = notifications;
}

pub fn clearDoneNotifications(notifications: *std.BoundedArray(Notify, 1024), nstime_since_last_frame: u64) void {
    if (notifications.len == 0) return;

    const second_diff = @intToFloat(f32, nstime_since_last_frame) / 1000000000;
    var i = notifications.len;
    while (i > 0) {
        i -= 1;

        var n = &notifications.slice()[i];
        n.remaining_time -= second_diff;

        if (n.remaining_time <= 0)
            _ = notifications.orderedRemove(i);
    }
}
