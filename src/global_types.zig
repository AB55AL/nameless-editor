const std = @import("std");
const ArrayList = std.ArrayList;

const Buffer = @import("editor/buffer.zig");
const Window = @import("ui/window.zig").Window;
const Windows = @import("ui/window.zig").Windows;
const OSWindow = @import("ui/window.zig").OSWindow;

pub const Global = struct {
    /// A Pointer to the currently focused buffer
    focused_buffer: *Buffer,
    /// An ArrayList holding pointers to all the buffers in the editor
    buffers: ArrayList(*Buffer),
    /// The buffer of the command_line
    command_line_buffer: *Buffer,
    command_line_is_open: bool = false,
};

pub const GlobalInternal = struct {
    /// Global allocator
    allocator: std.mem.Allocator,
    /// When a buffer is removed from global.buffers it is placed here
    buffers_trashcan: ArrayList(*Buffer),
    /// An ArrayList holding every visible window
    windows: Windows,
    /// The window of the command_line
    command_line_window: Window,
    /// The width and height of the window system window
    os_window: OSWindow,
};
