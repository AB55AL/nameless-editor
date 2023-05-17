const std = @import("std");

const editor_api = @import("../editor/editor.zig");

pub const BufferDisplayer = @import("buffer_display.zig");
pub usingnamespace @import("notify.zig");

pub const UserUI = *const fn (gpa: std.mem.Allocator, arena: std.mem.Allocator) void;

pub fn extraFrames() void {
    editor_api.gs().extra_frames = 2;
}

pub fn addUserUI(func: UserUI) void {
    _ = editor_api.gs().user_ui.getOrPut(editor_api.gs().allocator, func) catch return;
}

pub fn removeUserUI(func: UserUI) void {
    _ = editor_api.gs().user_ui.remove(func);
}

pub fn toggleBuffersUI() void {
    editor_api.gs().show_buffers = !editor_api.gs().show_buffers;
    editor_api.gs().focused_buffer_window = editor_api.gs().visiable_buffers_tree.root;
}

pub fn focusedCursorRect() ?editor_api.Rect {
    return editor_api.gs().focused_cursor_rect;
}

pub fn notify(comptime title_fmt: []const u8, title_values: anytype, comptime message_fmt: []const u8, message_values: anytype, time: f32) void {
    editor_api.gs().notifications.add(title_fmt, title_values, message_fmt, message_values, time) catch |err| std.debug.print("{!}\n", .{err});
}

pub fn putBufferDisplayer(file_type: []const u8, interface: BufferDisplayer) !void {
    const ft = try editor_api.stringStorageGetOrPut(file_type);
    try editor_api.gs().buffer_displayers.put(editor_api.gs().allocator, ft, interface);
}
