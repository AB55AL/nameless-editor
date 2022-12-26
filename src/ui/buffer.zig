const std = @import("std");
const print = std.debug.print;

const ui = @import("../globals.zig").ui;
const Buffer = @import("../editor/buffer.zig");

pub fn makeBufferVisable(buffer: *Buffer) void {
    for (ui.visiable_buffers) |b, i| {
        if (b == null) {
            ui.visiable_buffers[i] = buffer;
            break;
        }
    }
}
