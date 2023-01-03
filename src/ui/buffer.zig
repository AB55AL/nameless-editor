const std = @import("std");
const print = std.debug.print;

const ui_lib = @import("ui_lib.zig");
const ui = @import("../globals.zig").ui;
const Buffer = @import("../editor/buffer.zig");
const math = @import("math.zig");
const utils = @import("../utils.zig");

pub const BufferWindow = struct {
    buffer: *Buffer,
    first_visiable_row: u64,

    pub fn scrollDown(buffer_win: *BufferWindow, offset: u64) void {
        buffer_win.first_visiable_row += offset;
        buffer_win.first_visiable_row = std.math.min(
            buffer_win.buffer.lines.newlines_count,
            buffer_win.first_visiable_row,
        );
    }

    pub fn scrollUp(buffer_win: *BufferWindow, offset: u64) void {
        if (buffer_win.first_visiable_row < offset)
            buffer_win.first_visiable_row = 1
        else
            buffer_win.first_visiable_row -= offset;
    }
};

pub fn makeBufferVisable(buffer: *Buffer) void {
    for (ui.visiable_buffers) |b, i| {
        if (b == null) {
            ui.visiable_buffers[i] = .{
                .buffer = buffer,
                .first_visiable_row = 1,
            };
            break;
        }
    }
}

pub fn buffers(allocator: std.mem.Allocator, slices_of_arrays: [](?[]u8)) !void {
    const ww = @intToFloat(f32, ui.state.window_width);
    const wh = @intToFloat(f32, ui.state.window_height);

    var buffer_window_dim = math.Vec2(f32){ .x = ww, .y = wh };

    try ui_lib.layoutStart(allocator, ui_lib.Grid2x2.getLayout(), buffer_window_dim.x, buffer_window_dim.y, 0x272822);
    const max_lines = @floatToInt(u32, std.math.ceil(wh / ui.state.font.newLineOffset()));

    ui.state.max_id = 100;
    for (ui.visiable_buffers) |*buffer_win, i| {
        if (ui.visiable_buffers[i] == null) continue;
        var bw = &((buffer_win).* orelse continue);
        var buffer = bw.buffer;

        const cursor_row = @intCast(u32, buffer.getRowAndCol(buffer.cursor_index).row);
        var first_row = bw.first_visiable_row;
        var last_row = std.math.min(buffer.lines.newlines_count, first_row + max_lines - 1);

        if (cursor_row > last_row - 1) {
            bw.scrollDown(cursor_row - last_row);
        } else if (cursor_row < first_row) {
            bw.scrollUp(first_row - cursor_row);
        }
        first_row = bw.first_visiable_row;
        last_row = std.math.min(buffer.lines.newlines_count, first_row + max_lines);

        slices_of_arrays[i] = try buffer.getLines(allocator, first_row, last_row);
        var string = slices_of_arrays[i].?;
        var cursor_relative_to_string = if (first_row == 1) buffer.cursor_index else blk: {
            var diff = buffer.getLinesLength(1, first_row - 1);
            break :blk buffer.cursor_index - diff;
        };
        try bufferWidget(allocator, buffer, string, buffer_window_dim, cursor_relative_to_string);
    }
    try ui_lib.layoutEnd(ui_lib.Grid2x2.getLayout());
}

pub fn bufferWidget(allocator: std.mem.Allocator, buffer: *Buffer, content: []u8, dim: math.Vec2(f32), cursor_index: u64) !void {
    var string = content;
    var action = try ui_lib.textWithDim(
        allocator,
        string,
        cursor_index,
        dim,
        &.{ .clickable, .draggable, .highlight_text, .text_cursor, .clip, .render_background },
        ui_lib.Column.getLayout(),
        0x272822,
    );

    if (action.half_click and action.string_selection_range != null)
        buffer.cursor_index = action.string_selection_range.?.start;
}
