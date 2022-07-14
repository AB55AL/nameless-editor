const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const unicode = std.unicode;

const Cursor = @import("cursor.zig").Cursor;
const GapBuffer = @import("gap_buffer.zig");

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
lines: GapBuffer,
allocator: std.mem.Allocator,

history: History,
current_state: HistoryBufferStateResizeable,
next_state: HistoryBufferStateResizeable,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8, buf: []const u8) !*Buffer {
    var buffer = try allocator.create(Buffer);
    buffer.lines = try GapBuffer.init(allocator, null);
    buffer.cursor = .{ .row = 1, .col = 1 };
    buffer.allocator = allocator;
    buffer.file_path = try allocator.alloc(u8, file_path.len);
    std.mem.copy(u8, buffer.file_path, file_path);

    buffer.lines.moveGapPosAbsolute(0);
    try buffer.lines.insert(buf);
    buffer.lines.moveGapPosAbsolute(0);

    buffer.size = buf.len;
    buffer.history = History.init(allocator);
    buffer.current_state = HistoryBufferStateResizeable{
        .content = try GapBuffer.init(allocator, null),
        .first_row = buffer.cursor.row,
        .last_row = buffer.cursor.row,
    };
    buffer.next_state = HistoryBufferStateResizeable{
        .content = try GapBuffer.init(allocator, null),
        .first_row = buffer.cursor.row,
        .last_row = buffer.cursor.row,
    };
    return buffer;
}

pub fn deinit(buffer: *Buffer) void {
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

    var num_of_newlines: u32 = utils.countChar(buffer.lines.sliceOfContent(), '\n');

    if (row <= 0 or row > num_of_newlines)
        return error.IndexOutOfBounds;

    try without_history_change.insert(buffer, row, column, string);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn delete(buffer: *Buffer, row: u32, start_column: u32, end_column: u32) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("delete(): range out of bounds\n", .{});
        return error.IndexOutOfBounds;
    }

    try without_history_change.delete(buffer, row, start_column, end_column);
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    _ = buffer;
    _ = start_row;
    _ = end_row;
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row or start_col > end_col) {
        return error.IndexOutOfBounds;
    }
    _ = buffer;
}

// TODO: this
// pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
// }

// FIXME: Implement this correctly
pub fn copyOfRows(buffer: *Buffer, start_row: usize, end_row: usize) ![]u8 {
    _ = buffer;
    _ = start_row;
    _ = end_row;
    return buffer.lines.copy();
}

// FIXME: Implement this correctly
pub fn countCodePointsAtRow(buffer: *Buffer, row: u32) usize {
    if (buffer.lines.length() == 0) return 0;
    if (row > utils.countChar(buffer.lines.sliceOfContent(), '\n')) {
        unreachable;
    }

    const slice = utils.getLine(buffer.lines.sliceOfContent(), row);
    return unicode.utf8CountCodepoints(slice) catch unreachable;
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
