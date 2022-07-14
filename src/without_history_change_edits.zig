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
    try insureLastByteIsNewline(buffer);

    const index = utils.getIndex(buffer.lines.sliceOfContent(), row, start_column);
    const slice = utils.getLine(buffer.lines.sliceOfContent(), row);
    const substring = utf8.substringOfUTF8Sequence(slice, start_column, end_column - 1) catch unreachable;

    buffer.lines.moveGapPosAbsolute(index);
    buffer.lines.delete(substring.len);

    try insureLastByteIsNewline(buffer);
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    if (start_row > end_row)
        return error.InvalidRange;

    try insureLastByteIsNewline(buffer);

    var from = utils.getNewline(buffer.lines.sliceOfContent(), start_row - 1).?;
    var to = utils.getNewline(buffer.lines.sliceOfContent(), end_row) orelse buffer.lines.length();

    if (start_row == 1) to += 1; // FIXME: Find out why this is needed

    buffer.lines.moveGapPosAbsolute(from);
    buffer.lines.delete(to - from);

    try insureLastByteIsNewline(buffer);
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row or start_col > end_col)
        return error.InvalidRange;

    if (start_row == end_row) {
        try delete(buffer, start_row, start_col, end_col + 1);
    } else if (start_row == end_row - 1) {
        try delete(buffer, end_row, 1, end_col + 1);
        var line = utils.getLine(buffer.lines.sliceOfContent(), start_row);
        try delete(buffer, start_row, start_col, @intCast(u32, line.len + 1));
    } else {
        try delete(buffer, end_row, 1, end_col + 1);

        try deleteRows(buffer, start_row + 1, end_row - 1);

        var line = utils.getLine(buffer.lines.sliceOfContent(), start_row);
        try delete(buffer, start_row, start_col, @intCast(u32, line.len));
    }
}

fn insureLastByteIsNewline(buffer: *Buffer) !void {
    buffer.lines.moveGapPosRelative(-1);
    if (buffer.lines.content[buffer.lines.content.len - 1] != '\n' or
        buffer.lines.length() == 0)
    {
        buffer.lines.moveGapPosAbsolute(buffer.lines.length());
        try buffer.lines.insert("\n");
    }
}
