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
    var max_size = try notificationWindowSize(notifications);
    var rect = gui.Rect{
        .x = gui.currentWindow().wd.rect.w - max_size.w,
        .y = 5,
        .w = max_size.w,
        .h = max_size.h + 10,
    };

    var fw = try gui.floatingWindow(@src(), 0, false, &rect, null, .{});
    defer fw.deinit();

    var box = try gui.box(@src(), 0, .vertical, .{ .expand = .both });
    defer box.deinit();

    var options = gui.Options{};
    for (notifications, 0..) |*n, i| {
        var buf: [512]u8 = undefined;
        var dup = try std.fmt.bufPrint(&buf, "x{}", .{n.duplicates});

        var message_size = try options.fontGet().textSize(n.message);
        var title_size = try options.fontGet().textSize(n.title);

        if (try gui.button(@src(), i, "", .{ .background = false, .rect = .{ .y = box.childRect.y, .w = box.childRect.w, .h = message_size.h + title_size.h } })) {
            n.remaining_time = 0;
            continue;
        }

        {
            var hbox = try gui.box(@src(), i, .horizontal, .{});
            defer hbox.deinit();

            try gui.labelNoFmt(@src(), i, n.title, .{
                .margin = gui.Rect.all(0),
                .padding = gui.Rect.all(0),
                .font_style = .caption_heading,
            });

            _ = gui.spacer(@src(), i, .{ .w = 10 }, .{});

            try gui.labelNoFmt(@src(), i, dup, .{
                .margin = gui.Rect.all(0),
                .padding = gui.Rect.all(0),
            });
        }

        try gui.labelNoFmt(@src(), i, n.message, .{
            .margin = gui.Rect.all(0),
            .padding = gui.Rect.all(0),
        });

        _ = gui.spacer(@src(), i, .{ .h = 5 }, .{});
    }

    gui.cueFrame();
}

fn notificationWindowSize(notifications: []const Notify) !gui.Size {
    var max_size = gui.Size{ .w = 0, .h = 0 };

    var options = gui.Options{};
    for (notifications) |n| {
        var buf: [512]u8 = undefined;
        var dup = try std.fmt.bufPrint(&buf, "x{}", .{n.duplicates});

        var meseage_size = try options.fontGet().textSize(n.message);
        var title_size = try options.fontGet().textSize(n.title);
        var dup_size = try options.fontGet().textSize(dup);

        max_size.w = std.math.max3(meseage_size.w, title_size.w + dup_size.w, max_size.w);

        max_size.h += meseage_size.h;
        max_size.h += title_size.h;
    }
    max_size.h += 5 * @intToFloat(f32, notifications.len);

    return max_size;
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
