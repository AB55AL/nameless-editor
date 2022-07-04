const std = @import("std");
const print = std.debug.print;

const GapBuffer = @import("gap_buffer.zig").GapBuffer;
const Buffer = @import("buffer.zig");
const utils = @import("utils.zig");
const utf8 = @import("utf8.zig");

const end_of_line = std.math.maxInt(i32);

/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: i32, column: i32, string: []const u8) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("insert(): range out of bounds\n", .{});
        print("row {}\n", .{row});
        print("len {}\n", .{buffer.lines.length()});
        return;
    }

    var r = @intCast(usize, row - 1);
    var line = buffer.lines.elementAt(r);
    var c = @intCast(i32, utf8.arrayIndexOfCodePoint(line.sliceOfContent(), @intCast(usize, column)));
    // if (column > line.length()) {
    //     c = @intCast(i32, line.content.len);
    // }
    line.moveGapPosAbsolute(c);
    try line.insertMany(string);

    // Parse the new content and if needed spilt it into multiple lines

    var new_string = try line.copyOfContent();
    defer buffer.allocator.free(new_string);

    var iter = utils.splitAfter(u8, new_string, '\n');

    // Replace contents of the changed lines
    try line.replaceAllWith(iter.next().?);

    // Add new lines if there's any
    buffer.lines.moveGapPosAbsolute(@intCast(i32, r + 1));
    while (iter.next()) |new_line| {
        try buffer.lines.insertOne(try GapBuffer(u8).init(buffer.allocator, new_line));
    }
}

pub fn insertNewLine(buffer: *Buffer, row: i32, string: []const u8) !void {
    buffer.lines.moveGapPosAbsolute(row - 1);
    try buffer.lines.insertOne(try GapBuffer(u8).init(buffer.allocator, null));
    try insert(buffer, row, 1, string);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn delete(buffer: *Buffer, row: i32, start_column: i32, end_column: i32) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("delete(): range out of bounds\n", .{});
        return;
    }
    var lines = &buffer.lines;
    var r = @intCast(usize, row - 1);

    var line = lines.elementAt(r);

    var start_index = utf8.arrayIndexOfCodePoint(line.sliceOfContent(), @intCast(usize, start_column));
    var end_index = utf8.arrayIndexOfCodePoint(line.sliceOfContent(), @intCast(usize, std.math.min(
        end_column,
        line.length(),
    )));

    if (end_column > line.content.len) end_index += 1;

    var bytes_to_delete = @intCast(i32, end_index - start_index);

    line.moveGapPosAbsolute(@intCast(i32, start_index));
    line.delete(bytes_to_delete);

    if (line.isEmpty()) {
        lines.elementAt(r).deinit();
        lines.moveGapPosAbsolute(@intCast(i32, r));
        lines.delete(1);
        print("EMPTY\n", .{});

        // deleted the \n char
    } else if (line.getGapEndPos() == line.content.len - 1 and
        lines.length() >= 2 and
        r < lines.length() - 1)
    {
        try buffer.mergeRows(r, r + 1);
        lines.moveGapPosAbsolute(@intCast(i32, r + 1));
        lines.delete(1);
    }
}

pub fn deleteRange(buffer: *Buffer, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
    if (start_row == end_row) {
        try delete(buffer, start_row, start_col, end_col);
        return;
    }
    try delete(buffer, end_row, 1, end_col);

    var mid_row: i32 = end_row - 1;
    while (mid_row > start_row) : (mid_row -= 1) {
        try delete(buffer, mid_row, 1, end_of_line);
    }

    try delete(buffer, start_row, start_col, end_of_line);
}

pub fn deleteRows(buffer: *Buffer, start_row: i32, end_row: i32) !void {
    try deleteRange(buffer, start_row, 1, end_row, end_of_line);
}

pub fn replaceRows(buffer: *Buffer, string: []const u8, start_row: i32, end_row: i32) !void {
    try deleteRows(buffer, start_row, end_row);
    try insertNewLine(buffer, start_row, string);
}

pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
    try deleteRange(buffer, start_row, start_col, end_row, end_col);
    try insert(buffer, start_row, start_col, string);
}
