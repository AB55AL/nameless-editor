const std = @import("std");
const print = @import("std").debug.print;

const globals = @import("../globals.zig");
const command_line = @import("../editor/command_line.zig");
const Windows = @import("window.zig");
const Buffer = @import("../editor/buffer.zig");
const buffer_ops = @import("../editor/buffer_ops.zig");

const global = globals.global;
const internal = globals.internal;

pub fn openDrawerWindow(buffer: *Buffer, height: f32) void {
    global.previous_buffer_index = global.focused_buffer.index;
    global.drawer_buffer = buffer;
    global.focused_buffer = buffer;
    global.drawer_window_is_open = true;
    global.drawer_window.height = 1;
    global.drawer_window.y = height;
    global.drawer_window.buffer = buffer;
}

pub fn closeDrawerWindow() void {
    global.focused_buffer = buffer_ops.getBufferI(global.previous_buffer_index).?;
    global.drawer_window_is_open = false;
    global.drawer_window.height = 0.1;
    global.drawer_window.y = 0.95;
    global.drawer_window.buffer = global.command_line_buffer;
    global.drawer_buffer = global.command_line_buffer;
}
