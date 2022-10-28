const std = @import("std");
const print = std.debug.print;
const Buffer = @import("../editor/buffer.zig");
const Window = @import("window.zig").Window;

pub const VCursor = struct {
    pub fn convert(buffer: *Buffer, window: Window) VCursor {
        const cursor = buffer.getRowAndCol(buffer.cursor_index);

        var col = @intCast(i32, cursor.col) - @intCast(i32, window.start_col) + 1;
        col = std.math.max(0, col);
        var row = @intCast(i32, cursor.row) - @intCast(i32, window.start_row) + 1;
        row = std.math.max(0, row);

        return VCursor{
            .row = @intCast(u32, row),
            .col = @intCast(u32, col),
            .wrap_cursor = window.options.wrap_text,
        };
    }

    row: u32 = 1,
    col: u32 = 1,
    wrap_cursor: bool = false,
};
