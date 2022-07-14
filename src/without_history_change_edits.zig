const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;

const GapBuffer = @import("gap_buffer.zig").GapBuffer;
const Buffer = @import("buffer.zig");
const utils = @import("utils.zig");
const utf8 = @import("utf8.zig");

/// Inserts the given string at the given row and column. (1-based)
/// Doesn't modify the history
pub fn insert(buffer: *Buffer, row: u32, column: u32, string: []const u8) !void {
    const index = utils.getIndex(buffer.lines.sliceOfContent(), row, column);
    buffer.lines.moveGapPosAbsolute(index);
    try buffer.lines.insert(string);

    // Insure the last byte is a newline char
    buffer.lines.moveGapPosRelative(-1);
    if (buffer.lines.content[buffer.lines.content.len - 1] != '\n') {
        buffer.lines.moveGapPosAbsolute(buffer.lines.length());
        try buffer.lines.insert("\n");
    }
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
/// Doesn't modify the history
pub fn delete(buffer: *Buffer, row: u32, start_column: u32, end_column: u32) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("delete(): range out of bounds\n", .{});
        return error.IndexOutOfBounds;
    }

    const index = utils.getIndex(buffer.lines.sliceOfContent(), row, start_column);
    const slice = utils.getLine(buffer.lines.sliceOfContent(), row);
    const substring = utf8.substringOfUTF8Sequence(slice, start_column, end_column - 1) catch unreachable;

    buffer.lines.moveGapPosAbsolute(index);
    try buffer.lines.delete(substring.len);

    // Insure the last byte is a newline char
    buffer.lines.moveGapPosRelative(-1);
    if (buffer.lines.content[buffer.lines.content.len - 1] != '\n') {
        buffer.lines.moveGapPosAbsolute(buffer.lines.length());
        try buffer.lines.insert("\n");
    }
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    _ = buffer;
    _ = start_row;
    _ = end_row;
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row or start_col > end_col) {
        return error.InvalidPositions;
    }
    _ = buffer;
}
