const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;

const GapBuffer = @import("gap_buffer.zig").GapBuffer;
const Buffer = @import("buffer.zig");
const utils = @import("utils.zig");
const utf8 = @import("utf8.zig");

const end_of_line = std.math.maxInt(i32);

/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: u32, column: u32, string: []const u8) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("insert(): range out of bounds\n", .{});
        print("row {}\n", .{row});
        print("len {}\n", .{buffer.lines.length()});
        return;
    }

    var r = row - 1;
    var line = buffer.lines.elementAt(r);
    var c = utf8.firstByteOfCodeUnit(line.sliceOfContent(), column);

    line.moveGapPosAbsolute(c);
    try line.insertMany(string);

    // Parse the new content and if needed spilt it into multiple lines

    var new_string = try line.copyOfContent();
    defer buffer.allocator.free(new_string);

    var iter = utils.splitAfter(u8, new_string, '\n');

    // Replace contents of the changed lines
    try line.replaceAllWith(iter.next().?);

    // Add new lines if there's any
    buffer.lines.moveGapPosRelative(1);
    while (iter.next()) |new_line| {
        try buffer.lines.insertOne(try GapBuffer(u8).init(buffer.allocator, new_line));
    }
    buffer.lines.moveGapPosAbsolute(r);

    buffer.size += string.len;
}

pub fn insertNewLine(buffer: *Buffer, row: u32, string: []const u8) !void {
    buffer.lines.moveGapPosAbsolute(row - 1);
    try buffer.lines.insertOne(try GapBuffer(u8).init(buffer.allocator, null));
    try insert(buffer, row, 1, string);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn delete(buffer: *Buffer, row: u32, start_column: u32, end_column: u32) !void {
    if (row <= 0 or row > buffer.lines.length() or start_column <= 0) {
        print("delete(): range out of bounds\n", .{});
        return;
    }
    var lines = &buffer.lines;
    var r = row - 1;
    var line = lines.elementAt(r);

    var start_index = utf8.firstByteOfCodeUnit(line.sliceOfContent(), start_column);
    var substring_to_delete = try utf8.substringOfUTF8Sequence(line.sliceOfContent(), start_column, end_column - 1);

    var bytes_to_delete = substring_to_delete.len;

    line.moveGapPosAbsolute(start_index);
    line.delete(bytes_to_delete);
    buffer.size -= bytes_to_delete;

    if (line.isEmpty()) {
        lines.elementAt(r).deinit();
        lines.moveGapPosAbsolute(r);
        lines.delete(1);

        // deleted the \n char
    } else if (line.getGapEndPos() == line.content.len - 1 and
        lines.length() >= 2 and
        r < lines.length() - 1)
    {
        try buffer.mergeRows(r, r + 1);
        lines.moveGapPosAbsolute(r + 1);
        lines.delete(1);
    }
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row == end_row) {
        try delete(buffer, start_row, start_col, end_col);
        return;
    }
    try delete(buffer, end_row, 1, end_col);

    var mid_row = end_row - 1;
    while (mid_row > start_row) : (mid_row -= 1) {
        try delete(buffer, mid_row, 1, end_of_line);
    }

    try delete(buffer, start_row, start_col, end_of_line);
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    try deleteRange(buffer, start_row, 1, end_row, end_of_line);
}

pub fn replaceRows(buffer: *Buffer, string: []const u8, start_row: u32, end_row: u32) !void {
    try deleteRows(buffer, start_row, end_row);
    try insertNewLine(buffer, start_row, string);
}

pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    try deleteRange(buffer, start_row, start_col, end_row, end_col);
    try insert(buffer, start_row, start_col, string);
}
