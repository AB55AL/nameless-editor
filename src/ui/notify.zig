const std = @import("std");
const print = std.debug.print;

const math = @import("math.zig");
const ui_lib = @import("ui_lib.zig");
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
    var slice = ui.notifications.slice();
    var i: i64 = @intCast(i64, slice.len - 1);
    while (i >= 0) : (i -= 1) {
        var n = slice[@intCast(u64, i)];
        var m_dim = ui_lib.stringDimension(n.message);
        var t_dim = ui_lib.stringDimension(n.title);
        var biggest_dim = .{
            .x = std.math.max(m_dim.x, t_dim.x),
            .y = std.math.max(m_dim.y, t_dim.y),
        };

        _ = try ui_lib.textWithDimStart(allocator, n.title, 0, biggest_dim, &.{ .render_background, .clip, .render_text }, ui_lib.Column.getLayout(), 0, 0xFFFFFF);
        try ui_lib.textWithDimEnd();

        _ = try ui_lib.textWithDimStart(allocator, n.message, 0, biggest_dim, &.{ .render_background, .clip, .render_text }, ui_lib.Column.getLayout(), 0, 0xFFFFFF);
        try ui_lib.textWithDimEnd();
    }
}
