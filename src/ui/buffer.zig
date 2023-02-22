const std = @import("std");
const print = std.debug.print;

const ui_lib = @import("ui_lib.zig");
const ui = @import("../globals.zig").ui;
const editor = @import("../globals.zig").editor;
const Buffer = @import("../editor/buffer.zig");
const math = @import("math.zig");
const shapes2d = @import("shape2d.zig");
const utils = @import("../utils.zig");

pub const BufferWindow = struct {
    buffer: *Buffer,
    first_visiable_row: u64,
    cursor_row: u64 = 1,
    cursor_col: u64 = 1,

    pub fn absoluteBufferIndexFromRelative(buffer_win: *BufferWindow, relative: u64) u64 {
        if (buffer_win.first_visiable_row == 1) return relative;

        const offset: u64 = buffer_win.buffer.indexOfFirstByteAtRow(buffer_win.first_visiable_row);
        utils.assert(relative + offset <= buffer_win.buffer.lines.size, "You may have passed an absolute index into this function");
        return relative + offset;
    }

    pub fn relativeBufferIndexFromAbsolute(buffer_win: *BufferWindow, absolute: u64) u64 {
        if (buffer_win.first_visiable_row == 1) return absolute;

        const offset: u64 = buffer_win.buffer.indexOfFirstByteAtRow(buffer_win.first_visiable_row);
        return absolute - offset;
    }

    pub fn scrollDown(buffer_win: *BufferWindow, offset: u64) void {
        buffer_win.first_visiable_row += offset;
        buffer_win.first_visiable_row = std.math.min(
            buffer_win.buffer.lines.newlines_count,
            buffer_win.first_visiable_row,
        );
    }

    pub fn scrollUp(buffer_win: *BufferWindow, offset: u64) void {
        if (buffer_win.first_visiable_row <= offset)
            buffer_win.first_visiable_row = 1
        else
            buffer_win.first_visiable_row -= offset;
    }

    pub fn moveCursorRelativeColumn(buffer_window: *BufferWindow, col_offset: i64, stop_before_newline: bool, reset_selection: bool) void {
        buffer_window.buffer.moveRelativeColumn(col_offset, stop_before_newline);
        buffer_window.setWindowCursorToBuffer();
        if (reset_selection) buffer_window.buffer.resetSelection();
    }

    pub fn moveCursorRelativeRow(buffer_window: *BufferWindow, row_offset: i64, reset_selection: bool) void {
        buffer_window.buffer.moveRelativeRow(row_offset);
        buffer_window.setWindowCursorToBuffer();
        if (reset_selection) buffer_window.buffer.resetSelection();
    }

    pub fn vCursorIndex(buffer_win: *BufferWindow) u64 {
        var row = buffer_win.cursor_row;
        return buffer_win.buffer.getIndex(row, buffer_win.cursor_col);
    }

    pub fn setWindowCursorToBuffer(buffer_win: *BufferWindow) void {
        const rc = buffer_win.buffer.getRowAndCol(buffer_win.buffer.cursor_index);
        buffer_win.cursor_row = rc.row;
        buffer_win.cursor_col = rc.col;
        buffer_win.buffer.resetSelection();
    }
};

pub fn nextBufferWindow() void {
    if (&(ui.visiable_buffers[0] orelse return) == ui.focused_buffer_window) {
        ui.focused_buffer_window = &(ui.visiable_buffers[1] orelse return);
    } else {
        ui.focused_buffer_window = &(ui.visiable_buffers[0] orelse return);
    }
}

pub fn makeBufferVisable(buffer: *Buffer) void {
    for (ui.visiable_buffers, 0..) |b, i| {
        if (b == null) {
            ui.visiable_buffers[i] = .{
                .buffer = buffer,
                .first_visiable_row = 1,
            };
            ui.focused_buffer_window = &(ui.visiable_buffers[i].?);
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
    for (ui.visiable_buffers, 0..) |*buffer_win, i| {
        if (ui.visiable_buffers[i] == null) continue;
        var bw = &((buffer_win).* orelse continue);
        try ui_lib.layoutStart(allocator, ui_lib.DynamicRow.getLayout(), buffer_window_dim.x, buffer_window_dim.y, 0x272822);

        var r = ui.state.focused_widget.?.rect;
        try bufferWidget(allocator, bw, .{ .x = r.w, .y = r.h });
        try statusLine(allocator, bw.buffer);

        try ui_lib.layoutEnd(ui_lib.DynamicRow.getLayout());
    }
    try ui_lib.layoutEnd(ui_lib.Grid2x2.getLayout());
}

pub fn bufferWidget(allocator: std.mem.Allocator, buffer_window: *BufferWindow, dim: math.Vec2(f32)) !void {
    const color: u24 = if (ui.focused_buffer_window == buffer_window) 0x272822 else 0;
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
        .features_flags = &.{ .clickable, .draggable, .text_cursor, .clip, .render_background },
        .bg_color = color,
    });

    var widget = ui.state.focused_widget.?;
    const max_lines = @floatToInt(u32, std.math.ceil(widget.rect.h / ui.state.font.newLineOffset()));
    var first_row = buffer_window.first_visiable_row;
    var last_row = std.math.min(buffer.lines.newlines_count, first_row + max_lines - 1);

    if (ui.state.pass == .input_and_render) {
        var cursor_row = buffer_window.cursor_row;
        if (cursor_row > last_row - 1 or cursor_row < first_row) {
            buffer_window.cursor_row = buffer_window.first_visiable_row;
            buffer.cursor_index = buffer_window.vCursorIndex();
        }

        if (action.full_click) {
            ui.focused_buffer_window = buffer_window;
            buffer_window.buffer.cursor_index = buffer_window.vCursorIndex();
        } else if (ui.focused_buffer_window == buffer_window) {
            buffer_window.buffer.cursor_index = buffer_window.vCursorIndex();
        }

        ui_lib.capDragValuesToRect(widget);

        // FIXME: When keyboard input is received the drag_start and drag_end should be reset
        // so that the highlight gets removed
        if (!widget.drag_start.eql(widget.drag_end)) {
            // TODO: Merge this into the second while loop below.
            // The problem here is that the highlight of the text will draw over the text when done during the second loop
            var buffer_iter = buffer.LineIterator(first_row, last_row);
            var start_glyph: ?ui_lib.GlyphCoords = null;
            var end_glyph: ?ui_lib.GlyphCoords = null;

            var end_glyph_location_iter = ui_lib.locateGlyphCoordsIterator(widget.rect, widget.drag_end);
            var start_glyph_location_iter = ui_lib.locateGlyphCoordsIterator(widget.rect, widget.drag_start);
            while (buffer_iter.next()) |string| {
                if (end_glyph == null)
                    end_glyph = end_glyph_location_iter.findGlyph(string);

                if (start_glyph == null)
                    start_glyph = start_glyph_location_iter.findGlyph(string);
            }
            if (end_glyph != null and start_glyph != null) {
                try ui_lib.highlightText(widget, &action, start_glyph.?, end_glyph.?);
                buffer.setSelection(start_glyph.?.index.?, end_glyph.?.index.?);
            }
        } else if (buffer.selection_start != buffer.cursor_index) {
            var buffer_iter = buffer.LineIterator(first_row, last_row);
            var start_glyph: ?ui_lib.GlyphCoords = null;
            var end_glyph: ?ui_lib.GlyphCoords = null;

            var end_glyph_location_iter = ui_lib.locateGlyphCoordsByIndexIterator(widget.rect, buffer.cursor_index);
            var start_glyph_location_iter = ui_lib.locateGlyphCoordsByIndexIterator(widget.rect, buffer.selection_start);
            while (buffer_iter.next()) |string| {
                if (end_glyph != null and start_glyph != null) break;

                if (end_glyph == null)
                    end_glyph = end_glyph_location_iter.findCoords(string);

                if (start_glyph == null)
                    start_glyph = start_glyph_location_iter.findCoords(string);
            }

            if (end_glyph != null and start_glyph != null) {
                try ui_lib.highlightText(widget, &action, start_glyph.?, end_glyph.?);
            }
        }

        var buffer_iter = buffer.LineIterator(first_row, last_row);
        var glyph_location_iter = ui_lib.locateGlyphCoordsIterator(widget.rect, widget.drag_end);

        var index_coord_location_iter = ui_lib.locateGlyphCoordsByIndexIterator(widget.rect, buffer_window.relativeBufferIndexFromAbsolute(buffer_window.vCursorIndex()));

        var x: f32 = widget.rect.x;
        var y: f32 = widget.rect.y;

        while (buffer_iter.next()) |string| {
            var cursor_coords = shapes2d.Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };

            if (action.half_click or action.string_selection_range != null) {
                if (glyph_location_iter.findGlyph(string)) |coords| {
                    cursor_coords = coords.location;
                    if (coords.index) |i| {
                        buffer.cursor_index = buffer_window.absoluteBufferIndexFromRelative(i);
                        buffer_window.setWindowCursorToBuffer();
                        if (action.string_selection_range) |ssr| buffer.setSelection(ssr.start, ssr.end);
                    }
                }
            }

            if (index_coord_location_iter.findCoords(string)) |coords| {
                cursor_coords = coords.location;
            }

            try ui.state.draw_list.pushRect(cursor_coords.x, cursor_coords.y, cursor_coords.w, cursor_coords.h, 0xFF00AA, null);

            const new_pos = try ui.state.draw_list.pushText(ui.state.font, widget.rect, x, y, 0xFFFFFF, string, null);
            x = new_pos.x;
            y = new_pos.y;
        }
    }

    try ui_lib.widgetEnd();
}

pub fn statusLine(allocator: std.mem.Allocator, buffer: *Buffer) !void {
    try ui_lib.layoutStart(allocator, ui_lib.DynamicColumn.getLayout(), ui.state.focused_widget.?.rect.w, ui.state.font.newLineOffset(), 0x272822);

    var dim = ui_lib.stringDimension(buffer.metadata.file_path);
    dim.x += 10;
    _ = try ui_lib.textWithDim(
        allocator,
        buffer.metadata.file_path,
        0,
        dim,
        &.{ .clip, .render_background, .render_text },
        ui_lib.Column.getLayout(),
        0x272822,
        0xAAAAAA,
    );

    _ = try ui_lib.textWithDim(
        allocator,
        buffer.metadata.file_type,
        0,
        ui_lib.stringDimension(buffer.metadata.file_type),
        &.{ .clip, .render_background, .render_text },
        ui_lib.Column.getLayout(),
        0x272822,
        0xAAAAAA,
    );

    try ui_lib.layoutEnd(ui_lib.DynamicColumn.getLayout());
}
