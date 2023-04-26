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

pub fn focusBuffersUI() void {
    globals.ui.focus_buffers = true;
    globals.editor.focused_buffer_window = globals.editor.visiable_buffers_tree.root;
}

pub fn focusedCursorRect() ?Rect {
    return globals.ui.focused_cursor_rect;
}
