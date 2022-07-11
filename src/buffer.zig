const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const unicode = std.unicode;

const Cursor = @import("cursor.zig").Cursor;
const GapBuffer = @import("gap_buffer.zig").GapBuffer;

const without_history_change = @import("without_history_change_edits.zig");
const history = @import("history.zig");
const History = history.History;
const HistoryBufferState = history.HistoryBufferState;
const HistoryBufferStateResizeable = history.HistoryBufferStateResizeable;
const HistoryChange = history.HistoryChange;

const utils = @import("utils.zig");

const end_of_line = 69_420_666;

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
/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: u32, column: u32, string: []const u8) !void {
    if (builtin.mode == std.builtin.Mode.Debug) if (!unicode.utf8ValidateSlice(string)) unreachable;
    if (row <= 0 or row > buffer.lines.length()) {
        print("insert(): range out of bounds\n", .{});
        return error.IndexOutOfBounds;
    }

    var line = buffer.lines.elementAt(row - 1);
    var num_of_lines: u32 = utils.countChar(string, '\n');

    if (string.len == 1 and string[0] == '\n')
        try history.updateHistory(buffer)
    else
        try history.updateHistoryIfNeeded(buffer, row, row + num_of_lines);

    var current_state = &buffer.current_state;
    if (buffer.lines.length() > 0) {
        if (line.isEmpty())
            try buffer.updateState(current_state, row, row, true)
        else
            try buffer.updateState(current_state, row, row, false);
    }

    //////////////////////////////////////////////
    try without_history_change.insert(buffer, row, column, string);
    //////////////////////////////////////////////

    try buffer.next_state.content.replaceAllWith("");
    try buffer.updateState(&buffer.next_state, row, row + num_of_lines, false);

    if (string.len == 1 and string[0] == '\n')
        try history.updateHistory(buffer)
    else
        try history.updateHistoryIfNeeded(buffer, row, row + num_of_lines);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn delete(buffer: *Buffer, row: u32, start_column: u32, end_column: u32) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("delete(): range out of bounds\n", .{});
        return error.IndexOutOfBounds;
    }

    var line = buffer.lines.elementAt(row - 1);
    var max_col = try unicode.utf8CountCodepoints(line.sliceOfContent());

    if (start_column == max_col + 1 and row == buffer.lines.length())
        return;

    var delete_entire_line = if (start_column == 1 and end_column >= max_col) true else false;
    var delete_within_line = if (start_column > 1 and end_column < max_col) true else false;
    var delete_new_line_char = if (end_column >= max_col) true else false;

    var current_state = &buffer.current_state;
    if (delete_entire_line or delete_within_line) {
        try buffer.updateState(current_state, row, row, false);
    } else if (delete_new_line_char) {
        try buffer.updateState(current_state, row, row + 1, false);
    }

    //////////////////////////////////////////////
    try without_history_change.delete(buffer, row, start_column, end_column);
    //////////////////////////////////////////////

    max_col = try unicode.utf8CountCodepoints(line.sliceOfContent());

    var next_state = &buffer.next_state;
    try next_state.content.replaceAllWith("");
    if (delete_entire_line) {
        try buffer.updateState(next_state, row, row, true);
    } else if (delete_within_line or delete_new_line_char) {
        try buffer.updateState(next_state, row, row, false);
    }
    if (delete_entire_line or delete_new_line_char)
        try history.updateHistory(buffer);

    if (builtin.mode == std.builtin.Mode.Debug) {
        var slice = try buffer.lines.elementAt(row - 1).copyOfContent();
        defer buffer.allocator.free(slice);
        if (!unicode.utf8ValidateSlice(slice)) {
            unreachable;
        }
    }
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    _ = buffer;
    _ = start_row;
    _ = end_row;
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row) {
        return error.IndexOutOfBounds;
    }
    if (start_row <= 0 or end_row > buffer.lines.length()) {
        return error.IndexOutOfBounds;
    }

    var last_line = buffer.lines.elementAt(end_row - 1);
    var max_col = try unicode.utf8CountCodepoints(last_line.sliceOfContent());

    if (start_row == end_row) {
        try buffer.delete(start_row, start_col, end_col + 1);
        try history.updateHistory(buffer);
        return;
    } else if (start_col == 1 and end_col >= max_col) {
        try buffer.deleteRows(start_row, end_row);
        return;
    }

    try history.updateHistory(buffer);

    if (end_col < max_col) {
        try buffer.updateState(&buffer.current_state, start_row, end_row, false);
    } else if (end_col >= max_col) {
        try buffer.updateState(&buffer.current_state, start_row, end_row + 1, false);
    }

    //////////////////////////////////////////////
    try without_history_change.deleteRange(buffer, start_row, start_col, end_row, end_col);
    //////////////////////////////////////////////

    try buffer.updateState(&buffer.next_state, start_row, start_row, false);

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

pub fn copyOfRows(buffer: *Buffer, start_row: usize, end_row: usize) ![]u8 {
    var copy = ArrayList(u8).init(buffer.allocator);
    var end = std.math.min(end_row, buffer.lines.length());
    var i: usize = start_row - 1;
    while (i < end) : (i += 1) {
        try copy.appendSlice(buffer.lines.elementAt(i).sliceOfContent());
    }

    return copy.toOwnedSlice();
}

pub fn countCodePointsAtRow(buffer: *Buffer, row: u32) u32 {
    if (buffer.lines.length() == 0) return 0;

    const line = buffer.lines.elementAt(row - 1);
    const val = (unicode.utf8CountCodepoints(line.sliceOfContent()) catch unreachable) + 1;
    return @intCast(u32, val);
}

pub fn copyAll(buffer: *Buffer) ![]u8 {
    return buffer.copyOfRows(1, buffer.lines.length());
}

fn updateState(buffer: *Buffer, state: *HistoryBufferStateResizeable, start_row: u32, end_row: u32, is_empty: bool) !void {
    if (state.content.isEmpty()) {
        if (is_empty) {
            try state.content.replaceAllWith("");
        } else {
            var content = try buffer.copyOfRows(start_row, end_row);
            defer buffer.allocator.free(content);
            try state.content.replaceAllWith(content);
        }
        state.first_row = start_row;
        state.last_row = end_row;
    } else {
        try history.updateHistoryIfNeeded(buffer, start_row, end_row);
    }
}
