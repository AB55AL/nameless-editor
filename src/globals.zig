const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;

const Buffer = @import("editor/buffer.zig");
const window_ops = @import("ui/window_ops.zig");
const window = @import("ui/window.zig");
const Window = window.Window;
const Windows = window.Windows;
const OSWindow = @import("ui/window.zig").OSWindow;

pub const global = struct {
    /// A Pointer to the currently focused buffer
    pub var focused_buffer: *Buffer = undefined;
    /// An ArrayList holding pointers to all the buffers in the editor
    pub var buffers: ArrayList(*Buffer) = undefined;
    /// The buffer of the command_line
    pub var command_line_buffer: *Buffer = undefined;
    pub var command_line_is_open: bool = false;
    pub var layouts: StringArrayHashMap(window.LayoutInterface) = undefined;
    /// An ArrayList holding every visible window
    pub var windows: Windows = undefined;
};

pub const internal = struct {
    /// Global allocator
    pub var allocator: std.mem.Allocator = undefined;
    /// When a buffer is removed from global.buffers it is placed here
    pub var buffers_trashcan: ArrayList(*Buffer) = undefined;
    /// The window of the command_line
    pub var command_line_window: Window = undefined;
    /// The width and height of the window system window
    pub var os_window: OSWindow = undefined;
};

pub fn initGlobals(allocator: std.mem.Allocator, window_width: u32, window_height: u32) !void {
    internal.allocator = allocator;

    global.command_line_buffer = try internal.allocator.create(Buffer);
    global.command_line_buffer.* = try Buffer.init(internal.allocator, "", "");

    internal.buffers_trashcan = ArrayList(*Buffer).init(internal.allocator);
    internal.os_window = .{ .width = @intToFloat(f32, window_width), .height = @intToFloat(f32, window_height) };
    internal.command_line_window = .{
        .index = 0,
        .x = 0,
        .y = 0.95,
        .width = 1,
        .height = 0.1,
        .buffer = global.command_line_buffer,
    };

    global.windows.wins = ArrayList(Window).init(internal.allocator);
    global.buffers = ArrayList(*Buffer).init(internal.allocator);
    global.layouts = StringArrayHashMap(window.LayoutInterface).init(internal.allocator);
}

pub fn deinitGlobals() void {
    for (global.buffers.items) |buffer|
        buffer.deinitAndDestroy(internal.allocator);
    global.buffers.deinit();

    for (internal.buffers_trashcan.items) |buffer|
        internal.allocator.destroy(buffer);
    internal.buffers_trashcan.deinit();

    internal.windows.wins.deinit();
    global.command_line_buffer.deinitAndDestroy(internal.allocator);
    global.layouts.deinit();
}
