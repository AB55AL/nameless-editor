const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const buffer_ops = @import("editor/buffer_ops.zig");
const Buffer = @import("editor/buffer.zig");
const BufferNode = buffer_ops.BufferNode;

pub const global = struct {
    /// A Pointer to the currently focused buffer
    pub var focused_buffer: *Buffer = undefined;
    /// A linked list of all the buffers in the editor
    pub var first_buffer: ?*Buffer = undefined;
    /// The number of valid buffers in the linked list
    pub var valid_buffers_count: u32 = 0;
    /// The buffer of the command_line
    pub var command_line_buffer: *Buffer = undefined;
    pub var command_line_is_open: bool = undefined;
    pub var drawer_window_is_open: bool = undefined;
    pub var drawer_buffer: *Buffer = undefined;
    pub var previous_buffer_index: u32 = undefined;
};

pub const internal = struct {
    /// Global allocator
    pub var allocator: std.mem.Allocator = undefined;
};

pub fn initGlobals(allocator: std.mem.Allocator, window_width: u32, window_height: u32) !void {
    _ = window_width;
    _ = window_height;
    internal.allocator = allocator;
    global.command_line_is_open = false;
    global.drawer_window_is_open = false;
    global.command_line_buffer = try internal.allocator.create(Buffer);
    global.command_line_buffer.* = try Buffer.init(internal.allocator, "", "");
}

pub fn deinitGlobals() void {
    if (global.first_buffer) |first_buffer| {
        var buffer = first_buffer;
        while (buffer.next_buffer) |nb| {
            switch (buffer.state) {
                .valid => buffer.deinitAndDestroy(internal.allocator),
                .invalid => internal.allocator.destroy(buffer),
            }
            buffer = nb;
        } else {
            switch (buffer.state) {
                .valid => buffer.deinitAndDestroy(internal.allocator),
                .invalid => internal.allocator.destroy(buffer),
            }
        }
    }

    global.command_line_buffer.deinitAndDestroy(internal.allocator);
}
