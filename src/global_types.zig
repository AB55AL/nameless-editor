const std = @import("std");
const ArrayList = std.ArrayList;

const Buffer = @import("buffer.zig");

pub const Global = struct {
    /// A Pointer to the currently focused buffer
    focused_buffer: *Buffer,
    /// An ArrayList holding pointers to all the buffers in the editor
    buffers: ArrayList(*Buffer),
};

pub const GlobalInternal = struct {
    /// Global allocator
    allocator: std.mem.Allocator,
    /// When a buffer is removed from global.buffers it is placed here
    buffers_trashcan: ArrayList(*Buffer),
};
