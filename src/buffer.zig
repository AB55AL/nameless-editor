const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;

const Cursor = @import("cursor.zig").Cursor;
const GapBuffer = @import("gap_buffer.zig").GapBuffer;

const history = @import("history.zig");
const History = history.History;
const HistoryBufferState = history.HistoryBufferState;
const HistoryBufferStateResizeable = history.HistoryBufferStateResizeable;
const HistoryChange = history.HistoryChange;

const utils = @import("utils.zig");

const Buffer = @This();

cursor: Cursor,
/// The data structure holding every line in the buffer
lines: GapBuffer(GapBuffer(u8)),
allocator: std.mem.Allocator,

history: History,
current_state: HistoryBufferStateResizeable,
next_state: HistoryBufferStateResizeable,

pub fn init(allocator: std.mem.Allocator, file_name: []const u8) !*Buffer {
    var buffer = try allocator.create(Buffer);
    buffer.lines = try GapBuffer(GapBuffer(u8)).init(allocator, null);
    buffer.cursor = .{ .row = 1, .col = 1 };
    buffer.allocator = allocator;

    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();
    const metadata = try file.metadata();
    try file.seekTo(0);
    var buf = try file.readToEndAlloc(allocator, metadata.size());
    defer allocator.free(buf);

    buffer.lines.moveGapPosAbsolute(0);
    var line = utils.splitByLineIterator(buf);
    while (line != null) {
        try buffer.lines.insertOne(try GapBuffer(u8).init(allocator, line));
        line = utils.splitByLineIterator(buf);
    }
    buffer.lines.moveGapPosAbsolute(0);

    buffer.history = History.init(allocator);
    buffer.current_state = HistoryBufferStateResizeable{
        .content = try GapBuffer(u8).init(allocator, null),
        .first_row = buffer.cursor.row,
        .last_row = buffer.cursor.row,
    };
    buffer.next_state = HistoryBufferStateResizeable{
        .content = try GapBuffer(u8).init(allocator, null),
        .first_row = buffer.cursor.row,
        .last_row = buffer.cursor.row,
    };
    return buffer;
}

pub fn deinit(buffer: *Buffer) void {
    var lines = buffer.lines;
    lines.moveGapPosAbsolute(0);
    var i: usize = 0;
    while (i < lines.length()) : (i += 1) {
        lines.content[i + lines.getGapEndPos() + 1].deinit();
    }

    buffer.lines.deinit();
    buffer.current_state.content.deinit();
    buffer.next_state.content.deinit();
    buffer.history.deinit();
    buffer.allocator.destroy(buffer);
}

pub fn charAt(buffer: Buffer, row: i32, col: i32) ?u8 {
    if (buffer.lines.length() == 0) return null;
    var r = @intCast(usize, row - 1);
    var c = @intCast(usize, col - 1);

    var gbuffer = buffer.lines.elementAt(r);
    if (c >= gbuffer.content.length()) return null;
    return gbuffer.elementAt(c).*;
}

pub fn moveCursorRelative(buffer: *Buffer, row_offset: i32, col_offset: i32) void {
    if (buffer.lines.length() == 0) return;

    var new_row = buffer.cursor.row + row_offset;
    var new_col = buffer.cursor.col + col_offset;
    buffer.moveCursorAbsolute(new_row, new_col);
}

pub fn moveCursorAbsolute(buffer: *Buffer, row: i32, col: i32) void {
    if (buffer.lines.length() == 0) return;
    var new_row = row;
    var new_col = col;

    if (new_row <= 0) {
        new_row = 1;
    } else {
        new_row = std.math.min(new_row, buffer.lines.length());
    }

    const gbuffer = buffer.lines.elementAt(@intCast(usize, new_row - 1));
    if (new_col <= 0) {
        new_col = 1;
    } else {
        new_col = std.math.min(new_col, gbuffer.length());
    }

    buffer.cursor.row = new_row;
    buffer.cursor.col = new_col;
}

/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: i32, column: i32, string: []const u8) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("insert(): range out of bounds\n", .{});
        return;
    }

    var line = buffer.lines.elementAt(@intCast(usize, row - 1));
    var num_of_lines: i32 = @intCast(i32, utils.countChar(string, '\n'));

    var current_state = &buffer.current_state;
    var next_state = &buffer.next_state;

    try buffer.updateHistoryIfNeeded(row, row + num_of_lines);
    if (current_state.content.isEmpty()) {
        try current_state.content.replaceAllWith(line.sliceOfContent());
        current_state.first_row = row;
        current_state.last_row = row;
    }

    try buffer.insertWithoutHistoryChange(row, column, string);

    var next_state_content = try buffer.copyOfRows(row, row + num_of_lines);
    defer buffer.allocator.free(next_state_content);

    try next_state.content.replaceAllWith(next_state_content);
    next_state.first_row = row;
    next_state.last_row = row + num_of_lines;

    try buffer.updateHistoryIfNeeded(row, row + num_of_lines);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn delete(buffer: *Buffer, row: i32, start_column: i32, end_column: i32) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("delete(): range out of bounds\n", .{});
        return;
    }

    var line = buffer.lines.elementAt(@intCast(usize, row - 1));

    var end_row = if (end_column > line.length())
        row + 1
    else
        row;

    var current_state = &buffer.current_state;
    var next_state = &buffer.next_state;

    if (current_state.content.isEmpty()) {
        var content = if (end_row > row)
            try buffer.copyOfRows(row, end_row)
        else
            line.sliceOfContent();

        defer if (end_row > row) buffer.allocator.free(content);

        try current_state.content.replaceAllWith(content);
        current_state.first_row = row;
        current_state.last_row = end_row;
    } else {
        try buffer.updateHistoryIfNeeded(row, end_row);
    }

    try buffer.deleteWithoutHistoryChange(row, start_column, end_column);

    var next_state_content = if (start_column == 1 and end_column > line.length())
        ""
    else
        line.sliceOfContent();

    try next_state.content.replaceAllWith(next_state_content);
    next_state.first_row = row;
    next_state.last_row = row;

    if (end_row > row)
        try buffer.updateHistory();
}

pub fn deleteRange(buffer: *Buffer, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
    if (start_row > end_row) {
        print("deleteRange(): start_row needs to be less than end_row\n", .{});
        return;
    }
    if (start_row <= 0 or end_row > buffer.lines.length()) {
        print("deleteRange(): range out of bounds\n", .{});
        return;
    }

    try buffer.updateHistory();

    var last_line = buffer.lines.elementAt(@intCast(usize, end_row - 1));
    var delete_all = start_col == 1 and end_col >= last_line.length();
    var delete_mid_to_end = end_col >= last_line.length();
    var delete_begin_to_mid = start_col == 1;

    var current_state = &buffer.current_state;
    var next_state = &buffer.next_state;

    var current_state_content: []const u8 = undefined;
    var current_state_first_row = start_row;
    var current_state_last_row: i32 = undefined;

    if (delete_all) {
        current_state_content = try buffer.copyOfRows(start_row, end_row);
        current_state_last_row = end_row;
    } else if (delete_mid_to_end) {
        current_state_content = try buffer.copyOfRows(start_row, end_row + 1);
        current_state_last_row = end_row + 1;
    } else if (delete_begin_to_mid) {
        current_state_content = try buffer.copyOfRows(start_row, end_row);
        current_state_last_row = end_row;
    }

    defer buffer.allocator.free(current_state_content);

    try current_state.content.replaceAllWith(current_state_content);
    current_state.first_row = current_state_first_row;
    current_state.last_row = current_state_last_row;

    try buffer.deleteRangeWithoutHistoryChange(start_row, start_col, end_row, end_col);

    var next_state_content: []const u8 = undefined;
    var next_state_first_row = start_row;
    var next_state_last_row: i32 = undefined;

    if (delete_all) {
        next_state_content = "";
        next_state_last_row = start_row;
    } else if (delete_mid_to_end) {
        next_state_content = buffer.lines.elementAt(@intCast(usize, start_row - 1)).sliceOfContent();
        next_state_last_row = start_row;
    } else if (delete_begin_to_mid) {
        next_state_content = last_line.sliceOfContent();
        next_state_last_row = start_row;
    }

    try next_state.content.replaceAllWith(next_state_content);
    next_state.first_row = next_state_first_row;
    next_state.last_row = next_state_last_row;

    try buffer.updateHistory();
}

// TODO: this
// pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
// }

fn updateHistoryIfNeeded(buffer: *Buffer, first_row: i32, last_row: i32) !void {
    var current_state = &buffer.current_state;
    var next_state = &buffer.next_state;

    if (current_state.content.isEmpty()) return;

    if (current_state.first_row != first_row or current_state.last_row != last_row) {
        try buffer.history.updateHistory(HistoryChange{
            .previous_state = .{
                .content = try current_state.content.copyOfContent(),
                .first_row = current_state.first_row,
                .last_row = current_state.last_row,
            },
            .next_state = .{
                .content = try next_state.content.copyOfContent(),
                .first_row = next_state.first_row,
                .last_row = next_state.last_row,
            },
        });

        try current_state.content.replaceAllWith("");
        try next_state.content.replaceAllWith("");
    }
}

pub fn updateHistory(buffer: *Buffer) !void {
    var current_state = &buffer.current_state;

    if (current_state.content.isEmpty()) return;
    try buffer.history.updateHistory(HistoryChange{
        .previous_state = .{
            .content = try current_state.content.copyOfContent(),
            .first_row = current_state.first_row,
            .last_row = current_state.last_row,
        },
        .next_state = .{
            .content = try buffer.next_state.content.copyOfContent(),
            .first_row = buffer.next_state.first_row,
            .last_row = buffer.next_state.last_row,
        },
    });

    try current_state.content.replaceAllWith("");
    current_state.first_row = buffer.cursor.row;
    current_state.last_row = buffer.cursor.row;
}

/// Merges two rows
pub fn mergeRows(buffer: *Buffer, first_row: usize, second_row: usize) !void {
    var next_line = buffer.lines.elementAt(second_row);
    var current_line = buffer.lines.elementAt(first_row);

    var str = try next_line.copyOfContent();

    current_line.moveGapPosRelative(@intCast(i32, current_line.content.len));
    try current_line.insertMany(str);
    current_line.moveGapPosAbsolute(0); // don't know why but if i don't do this the rendering looks wrong

    buffer.allocator.free(str);
    buffer.allocator.free(next_line.content);
}

pub fn copyOfRows(buffer: *Buffer, start_row: i32, end_row: i32) ![]u8 {
    var copy = ArrayList(u8).init(buffer.allocator);

    var i: usize = @intCast(usize, start_row - 1);
    while (i < end_row) : (i += 1) {
        try copy.appendSlice(buffer.lines.elementAt(i).sliceOfContent());
    }

    return copy.toOwnedSlice();
}

/// Inserts the given string at the given row and column. (1-based)
pub fn insertWithoutHistoryChange(buffer: *Buffer, row: i32, column: i32, string: []const u8) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("insertWithoutHistoryChange(): range out of bounds\n", .{});
        print("row {}\n", .{row});
        print("len {}\n", .{buffer.lines.length()});
        return;
    }

    var r = @intCast(usize, row - 1);
    var c = @intCast(i32, column - 1);
    var gbuffer = buffer.lines.elementAt(r);
    gbuffer.moveGapPosAbsolute(c);
    try gbuffer.insertMany(string);

    // Parse the new content and if needed spilt it into multiple lines

    var new_string = try gbuffer.copyOfContent();
    defer buffer.allocator.free(new_string);

    var line = utils.splitByLineIterator(new_string);

    // Replace contents of the changed lines
    try gbuffer.replaceAllWith(line.?);

    line = utils.splitByLineIterator(new_string);
    if (line == null) return;

    // Add new lines if there's any
    buffer.lines.moveGapPosAbsolute(@intCast(i32, r + 1));
    while (line != null) {
        try buffer.lines.insertOne(try GapBuffer(u8).init(buffer.allocator, line.?));
        line = utils.splitByLineIterator(new_string);
    }
}

pub fn insertNewLineWithoutHistoryChange(buffer: *Buffer, row: i32, string: []const u8) !void {
    buffer.lines.moveGapPosAbsolute(row - 1);
    try buffer.lines.insertOne(try GapBuffer(u8).init(buffer.allocator, null));
    try buffer.insertWithoutHistoryChange(row, 1, string);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn deleteWithoutHistoryChange(buffer: *Buffer, row: i32, start_column: i32, end_column: i32) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("deleteWithoutHistoryChange(): range out of bounds\n", .{});
        return;
    }
    var lines = &buffer.lines;
    var r = @intCast(usize, row - 1);
    var start_col = @intCast(i32, start_column - 1);
    var num_to_delete = end_column - start_col - 1;

    var gbuffer = lines.elementAt(r);

    gbuffer.moveGapPosAbsolute(start_col);
    gbuffer.delete(num_to_delete);

    if (gbuffer.isEmpty()) {
        lines.elementAt(r).deinit();
        lines.moveGapPosAbsolute(@intCast(i32, r));
        lines.delete(1);

        // deleted the \n char
    } else if (gbuffer.getGapEndPos() == gbuffer.content.len - 1 and
        lines.length() >= 2 and
        r < lines.length() - 1)
    { // merge this line with the next
        try buffer.mergeRows(r, r + 1);
        lines.moveGapPosAbsolute(@intCast(i32, r + 1));
        lines.delete(1);
    }
}

pub fn deleteRangeWithoutHistoryChange(buffer: *Buffer, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
    const end_of_line = std.math.maxInt(i32);

    if (start_row == end_row) {
        try buffer.deleteWithoutHistoryChange(start_row, start_col, end_of_line);
        return;
    }
    try buffer.deleteWithoutHistoryChange(end_row, 1, end_col);

    var mid_row: i32 = end_row - 1;
    while (mid_row > start_row) : (mid_row -= 1) {
        try buffer.deleteWithoutHistoryChange(mid_row, 1, end_of_line);
    }

    try buffer.deleteWithoutHistoryChange(start_row, start_col, end_of_line);
}

pub fn deleteRowsWithoutHistoryChange(buffer: *Buffer, start_row: i32, end_row: i32) !void {
    const end_of_line = std.math.maxInt(i32);
    try buffer.deleteRangeWithoutHistoryChange(start_row, 1, end_row, end_of_line);
}

pub fn replaceRowsWithoutHistoryChange(buffer: *Buffer, string: []const u8, start_row: i32, end_row: i32) !void {
    const end_of_line = std.math.maxInt(i32);
    try buffer.deleteRangeWithoutHistoryChange(start_row, 1, end_row, end_of_line);
    try buffer.insertNewLineWithoutHistoryChange(start_row, string);
}

pub fn replaceRangeWithoutHistoryChange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
    try buffer.deleteRangeWithoutHistoryChange(start_row, start_col, end_row, end_col);
    try buffer.insertWithoutHistoryChange(start_row, start_col, string);
}
