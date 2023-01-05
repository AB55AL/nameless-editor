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

pub fn buffers(allocator: std.mem.Allocator) !void {
    const ww = @intToFloat(f32, ui.state.window_width);
    const wh = @intToFloat(f32, ui.state.window_height);

    var buffer_window_dim = math.Vec2(f32){ .x = ww, .y = wh };

    try ui_lib.layoutStart(allocator, ui_lib.Grid2x2.getLayout(), buffer_window_dim.x, buffer_window_dim.y, 0x272822);

    ui.state.max_id = 100;
    for (ui.visiable_buffers) |*buffer_win, i| {
        if (ui.visiable_buffers[i] == null) continue;
        var bw = &((buffer_win).* orelse continue);
        try bufferWidget(allocator, bw, buffer_window_dim);
    }
    try ui_lib.layoutEnd(ui_lib.Grid2x2.getLayout());
}

pub fn bufferWidget(allocator: std.mem.Allocator, buffer_window: *BufferWindow, dim: math.Vec2(f32)) !void {
    var buffer = buffer_window.buffer;

    const id = ui_lib.newId();
    var action = try ui_lib.widgetStart(.{
        .allocator = allocator,
        .id = id,
        .layout = ui_lib.Column.getLayout(),
        .w = dim.x,
        .h = dim.y,
        .string = null,
        .cursor_index = 0,
        .features_flags = &.{ .clickable, .draggable, .highlight_text, .text_cursor, .clip, .render_background },
        .bg_color = 0x272822,
    });

    const max_lines = @floatToInt(u32, std.math.ceil(@intToFloat(f32, ui.state.window_height) / ui.state.font.newLineOffset()));
    const cursor_row = @intCast(u32, buffer.getRowAndCol(buffer.cursor_index).row);
    var first_row = buffer_window.first_visiable_row;
    var last_row = std.math.min(buffer.lines.newlines_count, first_row + max_lines - 1);

    if (cursor_row > last_row - 1) {
        buffer_window.scrollDown(cursor_row - last_row);
    } else if (cursor_row < first_row) {
        buffer_window.scrollUp(first_row - cursor_row);
    }
    first_row = buffer_window.first_visiable_row;
    last_row = std.math.min(buffer.lines.newlines_count, first_row + max_lines);
    var widget = ui.state.focused_widget.?;

    if (ui.state.pass == .input_and_render) {
        var x: f32 = widget.rect.x;
        var y: f32 = widget.rect.y;

        ui_lib.capDragValuesToRect(widget);
        var iter_2 = buffer.lineIterator(first_row, last_row);
        var end_glyph = ui_lib.locateGlyphCoordsWithIterator(Buffer.BufferIteratorType, widget.drag_end, &iter_2, widget.rect);
        try ui.state.draw_list.pushRect(end_glyph.location.x, end_glyph.location.y, end_glyph.location.w, end_glyph.location.h, 0xFF00AA, null);

        iter_2 = buffer.lineIterator(first_row, last_row);
        var start_glyph = if (widget.drag_start.eql(widget.drag_end)) end_glyph else ui_lib.locateGlyphCoordsWithIterator(Buffer.BufferIteratorType, widget.drag_start, &iter_2, widget.rect);
        try ui_lib.highlightText(widget, &action, start_glyph, end_glyph);

        var iter = buffer.lineIterator(first_row, last_row);
        while (iter.next()) |string| {
            var new_pos = try ui.state.draw_list.pushText(ui.state.font, widget.rect, x, y, 0xFFFFFF, string, null);
            x = new_pos.x;
            y = new_pos.y;
        }

        if (action.half_click and action.string_selection_range != null) {
            if (end_glyph.index) |i| buffer.cursor_index = i;
        }
    }

    try ui_lib.widgetEnd();
}
