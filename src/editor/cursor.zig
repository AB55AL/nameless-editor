const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const min = std.math.min;
const max = std.math.max;

const utils = @import("utils.zig");

const Buffer = @import("buffer.zig");

pub const Cursor = @This();
row: u64,
col: u64,
index: u64,

pub fn moveRelative(buffer: *Buffer, row_offset: i64, col_offset: i64) void {
    if (buffer.lines.size == 0) return;

    var new_row = @intCast(i64, buffer.cursor.row) + row_offset;
    var new_col = @intCast(i64, buffer.cursor.col) + col_offset;

    if (row_offset < 0) new_row = max(1, new_row);
    if (col_offset < 0) new_col = max(1, new_col);

    Cursor.moveAbsolute(buffer, @intCast(u64, new_row), @intCast(u64, new_col));
}

pub fn moveAbsolute(buffer: *Buffer, row: ?u64, col: ?u64) void {
    if (buffer.lines.size == 0) return;

    var new_row = if (row) |r| r else buffer.cursor.row;

    if (row != null) {
        if (new_row <= 1)
            new_row = 1
        else
            new_row = min(new_row, buffer.lines.newlines_count);

        buffer.cursor.row = new_row;
    }

    if (col) |c| {
        var new_col = c;
        if (new_col <= 1) {
            new_col = 1;
        } else {
            var max_col = buffer.countCodePointsAtRow(new_row) + 1;
            new_col = min(new_col, max_col);
        }
        buffer.cursor.col = new_col;
    }

    buffer.cursor.index = buffer.getIndex(buffer.cursor.row, buffer.cursor.col);
}

// TODO: Implement this
pub fn moveToEndOfLine(buffer: *Buffer) void {
    if (buffer.lines.length() == 0) return;
}

// TODO: Implement this
pub fn moveToStartOfLine(buffer: *Buffer) void {
    if (buffer.lines.size == 0) return;
}

/// Resets the cursor position to a valid position in the buffer
pub fn resetPosition(buffer: *Buffer) void {
    if (buffer.lines.length() == 0) return;
    var cursor = &buffer.cursor;

    if (cursor.row > buffer.lines.length()) {
        cursor.row = @intCast(u32, buffer.lines.length());
    }

    var max_col = buffer.countCodePointsAtRow(cursor.row);
    if (cursor.col > max_col) {
        moveAbsolute(buffer, null, max_col);
    }
}
