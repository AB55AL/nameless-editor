const std = @import("std");
const print = @import("std").debug.print;

const globals = @import("../globals.zig");
const command_line = @import("../editor/command_line.zig");
const Windows = @import("window.zig");
const Buffer = @import("../editor/buffer.zig");

const global = globals.global;
const internal = globals.internal;

pub const Direction = enum(u3) {
    here,
    right,
    left,
    above,
    below,
    next,
    prev,
};

pub fn closeFocusedWindow() void {
    var windows = global.windows;
    if (windows.wins.items.len == 0) return;
    var window_index = windows.focusedWindow().index;
    windows.closeWindow(window_index);
}

pub fn closeBufferWindow(buffer: *Buffer) void {
    for (global.windows.wins.items) |*win|
        if (buffer.index == win.buffer.index)
            global.windows.closeWindow(win.index);
}
