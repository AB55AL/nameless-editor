const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;

const Cursor = @import("cursor.zig").Cursor;
const GapBuffer = @import("gap_buffer.zig").GapBuffer;

const with_history_change = @import("without_history_change_edits.zig");
const history = @import("history.zig");
const History = history.History;
const HistoryBufferState = history.HistoryBufferState;
const HistoryBufferStateResizeable = history.HistoryBufferStateResizeable;
const HistoryChange = history.HistoryChange;

const utils = @import("utils.zig");
const utf8 = @import("utf8.zig");

const end_of_line = std.math.maxInt(i32);

const Buffer = @This();

file_path: []u8,
size: usize,
cursor: Cursor,
/// The data structure holding every line in the buffer
lines: GapBuffer(GapBuffer(u8)),
allocator: std.mem.Allocator,

history: History,
current_state: HistoryBufferStateResizeable,
next_state: HistoryBufferStateResizeable,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8, buf: []const u8) !*Buffer {
    var buffer = try allocator.create(Buffer);
    buffer.lines = try GapBuffer(GapBuffer(u8)).init(allocator, null);
    buffer.cursor = .{ .row = 1, .col = 1 };
    buffer.allocator = allocator;
    buffer.file_path = try allocator.alloc(u8, file_path.len);
    std.mem.copy(u8, buffer.file_path, file_path);

    buffer.lines.moveGapPosAbsolute(0);
    var iter = utils.splitAfter(u8, buf, '\n');
    while (iter.next()) |line| {
        try buffer.lines.insertOne(try GapBuffer(u8).init(allocator, line));
    }
    buffer.lines.moveGapPosAbsolute(0);

    buffer.size = buf.len;
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
    buffer.allocator.free(buffer.file_path);
    buffer.allocator.destroy(buffer);
}

pub fn moveCursorRelative(buffer: *Buffer, row_offset: i32, col_offset: i32) void {
    if (buffer.lines.length() == 0) return;

    var new_row = @intCast(i32, buffer.cursor.row) + row_offset;
    var new_col = @intCast(i32, buffer.cursor.col) + col_offset;

    new_row = if (new_row <= 0) 1 else new_row;
    new_col = if (new_row <= 0) 1 else new_col;

    buffer.moveCursorAbsolute(@intCast(u32, new_row), @intCast(u32, new_col));
}

pub fn moveCursorAbsolute(buffer: *Buffer, row: u32, col: u32) void {
    if (buffer.lines.length() == 0) return;
    var new_row = row;
    var new_col = col;

    if (new_row <= 0) {
        new_row = 1;
    } else {
        new_row = std.math.min(new_row, buffer.lines.length());
    }

    const line = buffer.lines.elementAt(new_row - 1);
    if (new_col <= 0) {
        new_col = 1;
    } else {
        new_col = std.math.min(new_col, utf8.numOfChars(line.sliceOfContent()));
    }

    buffer.cursor.row = new_row;
    buffer.cursor.col = new_col;
}

/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: u32, column: u32, string: []const u8) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("insert(): range out of bounds\n", .{});
        return;
    }

    var line = buffer.lines.elementAt(row - 1);
    var num_of_lines: u32 = utils.countChar(string, '\n');

    var current_state = &buffer.current_state;
    var next_state = &buffer.next_state;

    try history.updateHistoryIfNeeded(buffer, row, row + num_of_lines);
    if (current_state.content.isEmpty()) {
        try current_state.content.replaceAllWith(line.sliceOfContent());
        current_state.first_row = row;
        current_state.last_row = row;
    }

    try with_history_change.insert(buffer, row, column, string);

    var next_state_content = try buffer.copyOfRows(row, row + num_of_lines);
    defer buffer.allocator.free(next_state_content);

    try next_state.content.replaceAllWith(next_state_content);
    next_state.first_row = row;
    next_state.last_row = row + num_of_lines;

    try history.updateHistoryIfNeeded(buffer, row, row + num_of_lines);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn delete(buffer: *Buffer, row: u32, start_column: u32, end_column: u32) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("delete(): range out of bounds\n", .{});
        return;
    }

    var line = buffer.lines.elementAt(row - 1);

    var end_row = if (end_column > utf8.numOfChars(line.sliceOfContent()))
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
        try history.updateHistoryIfNeeded(buffer, row, end_row);
    }

    try with_history_change.delete(buffer, row, start_column, end_column);

    var next_state_content = if (start_column == 1 and end_column > utf8.numOfChars(line.sliceOfContent()))
        ""
    else
        line.sliceOfContent();

    try next_state.content.replaceAllWith(next_state_content);
    next_state.first_row = row;
    next_state.last_row = row;

    if (end_row > row)
        try history.updateHistory(buffer);
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row) {
        print("deleteRange(): start_row needs to be less than end_row\n", .{});
        return;
    }
    if (start_row <= 0 or end_row > buffer.lines.length()) {
        print("deleteRange(): range out of bounds\n", .{});
        return;
    }

    try history.updateHistory(buffer);

    var last_line = buffer.lines.elementAt(end_row - 1);
    var delete_all = start_col == 1 and end_col >= utf8.numOfChars(last_line.sliceOfContent());
    var delete_mid_to_end = end_col >= utf8.numOfChars(last_line.sliceOfContent());
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

    try with_history_change.deleteRange(buffer, start_row, start_col, end_row, end_col);

    var next_state_content: []const u8 = undefined;
    var next_state_first_row = start_row;
    var next_state_last_row: i32 = undefined;

    if (delete_all) {
        next_state_content = "";
        next_state_last_row = start_row;
    } else if (delete_mid_to_end) {
        next_state_content = buffer.lines.elementAt(start_row - 1).sliceOfContent();
        next_state_last_row = start_row;
    } else if (delete_begin_to_mid) {
        next_state_content = last_line.sliceOfContent();
        next_state_last_row = start_row;
    }

    try next_state.content.replaceAllWith(next_state_content);
    next_state.first_row = next_state_first_row;
    next_state.last_row = next_state_last_row;

    try history.updateHistory(buffer);
}

// TODO: this
// pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
// }

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

pub fn copyOfRows(buffer: *Buffer, start_row: u32, end_row: u32) ![]u8 {
    var copy = ArrayList(u8).init(buffer.allocator);

    var i: usize = start_row - 1;
    while (i < end_row) : (i += 1) {
        try copy.appendSlice(buffer.lines.elementAt(i).sliceOfContent());
    }

    return copy.toOwnedSlice();
}
