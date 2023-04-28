const std = @import("std");

const globals = @import("../globals.zig");
const Rect = @import("../editor/buffer_window.zig").Rect;

pub usingnamespace @import("notify.zig");

pub const UserUI = *const fn (gpa: std.mem.Allocator, arena: std.mem.Allocator) void;

pub fn extraFrame() void {
    globals.internal.extra_frame = true;
}

pub fn addUserUI(func: UserUI) void {
    _ = globals.ui.user_ui.getOrPut(globals.internal.allocator, func) catch return;
}

pub fn removeUserUI(func: UserUI) void {
    _ = globals.ui.user_ui.remove(func);
}

pub fn toggleBuffersUI() void {
    globals.ui.show_buffers = !globals.ui.show_buffers;
    globals.editor.focused_buffer_window = globals.editor.visiable_buffers_tree.root;
}

pub fn focusedCursorRect() ?Rect {
    return globals.ui.focused_cursor_rect;
}

pub fn notify(comptime title_fmt: []const u8, title_values: anytype, comptime message_fmt: []const u8, message_values: anytype, time: f32) void {
    globals.ui.notifications.add(title_fmt, title_values, message_fmt, message_values, time) catch |err| std.debug.print("{!}\n", .{err});
}
