const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const Buffer = @import("buffer.zig");
const GapBuffer = @import("gap_buffer.zig").GapBuffer;

pub const HistoryBufferState = struct {
    content: []const u8,
    first_row: i32,
    last_row: i32,
};

pub const HistoryBufferStateResizeable = struct {
    content: GapBuffer(u8),
    first_row: i32,
    last_row: i32,
};

pub const HistoryChange = struct {
    previous_state: HistoryBufferState,
    next_state: HistoryBufferState,
};

pub const History = struct {
    stack: ArrayList(HistoryChange),
    redo_stack: ArrayList(HistoryChange),

    pub fn init(allocator: std.mem.Allocator) History {
        return History{
            .stack = ArrayList(HistoryChange).init(allocator),
            .redo_stack = ArrayList(HistoryChange).init(allocator),
        };
    }

    pub fn deinit(history: *History) void {
        const free = history.stack.allocator.free;
        for (history.stack.items) |item| {
            free(item.previous_state.content);
            free(item.next_state.content);
        }
        for (history.redo_stack.items) |item| {
            free(item.previous_state.content);
            free(item.next_state.content);
        }
        history.redo_stack.deinit();
        history.stack.deinit();
    }

    pub fn updateHistory(history: *History, latest_change: HistoryChange) !void {
        history.emptyRedoStack();
        try history.pushChange(latest_change);
    }

    pub fn peekStack(stack: ArrayList(HistoryChange)) HistoryChange {
        return stack.items[stack.items.len - 1];
    }

    fn emptyRedoStack(history: *History) void {
        const free = history.stack.allocator.free;
        while (history.redo_stack.popOrNull()) |item| {
            free(item.previous_state.content);
            free(item.next_state.content);
        }
    }

    fn pushChange(history: *History, the_change: HistoryChange) !void {
        try history.stack.append(the_change);
    }
};

pub fn undo(buffer: *Buffer) !void {
    if (buffer.history.stack.items.len == 0) return;

    var the_change = buffer.history.stack.pop();
    var next_state = the_change.next_state;
    var previous_state = the_change.previous_state;

    if (next_state.content.len == 0) {
        try buffer.insertNewLineWithoutHistoryChange(
            previous_state.first_row,
            previous_state.content,
        );
    } else if (previous_state.content.len == 0) {
        try buffer.deleteRowsWithoutHistoryChange(
            previous_state.first_row,
            previous_state.last_row,
        );
    } else {
        try buffer.replaceRowsWithoutHistoryChange(
            previous_state.content,
            next_state.first_row,
            next_state.last_row,
        );
    }

    try buffer.history.redo_stack.append(the_change);
}

pub fn redo(buffer: *Buffer) !void {
    if (buffer.history.redo_stack.items.len == 0) return;

    var the_change = buffer.history.redo_stack.pop();
    var next_state = the_change.next_state;
    var previous_state = the_change.previous_state;

    if (next_state.content.len == 0) {
        try buffer.deleteRowsWithoutHistoryChange(
            previous_state.first_row,
            previous_state.last_row,
        );
    } else if (previous_state.content.len == 0) {
        try buffer.insertNewLineWithoutHistoryChange(
            previous_state.first_row,
            next_state.content,
        );
    } else {
        try buffer.replaceRowsWithoutHistoryChange(
            next_state.content,
            previous_state.first_row,
            previous_state.last_row,
        );
    }

    try buffer.history.stack.append(the_change);
}
