const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const Buffer = @import("buffer.zig");
const GapBuffer = @import("gap_buffer.zig").GapBuffer;
const without_history_change = @import("without_history_change_edits.zig");

pub const HistoryBufferState = struct {
    content: []const u8,
    first_row: u32,
    last_row: u32,
};

pub const HistoryBufferStateResizeable = struct {
    content: GapBuffer(u8),
    first_row: u32,
    last_row: u32,
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

    fn update(history: *History, latest_change: HistoryChange) !void {
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
        try without_history_change.insertNewLine(
            buffer,
            previous_state.first_row,
            previous_state.content,
        );
    } else if (previous_state.content.len == 0) {
        try without_history_change.deleteRows(
            buffer,
            previous_state.first_row,
            previous_state.last_row,
        );
    } else {
        try without_history_change.replaceRows(
            buffer,
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
        try without_history_change.deleteRows(
            buffer,
            previous_state.first_row,
            previous_state.last_row,
        );
    } else if (previous_state.content.len == 0) {
        try without_history_change.insertNewLine(
            buffer,
            previous_state.first_row,
            next_state.content,
        );
    } else {
        try without_history_change.replaceRows(
            buffer,
            next_state.content,
            previous_state.first_row,
            previous_state.last_row,
        );
    }

    try buffer.history.stack.append(the_change);
}

pub fn updateHistoryIfNeeded(buffer: *Buffer, first_row: u32, last_row: u32) !void {
    var current_state = &buffer.current_state;
    if (current_state.content.isEmpty()) return;

    if (current_state.first_row != first_row and current_state.last_row != last_row)
        try updateHistory(buffer);
}

pub fn updateHistory(buffer: *Buffer) !void {
    var current_state = &buffer.current_state;
    var next_state = &buffer.next_state;

    if (current_state.content.isEmpty()) return;
    try buffer.history.update(HistoryChange{
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
    current_state.first_row = buffer.cursor.row;
    current_state.last_row = buffer.cursor.row;

    try next_state.content.replaceAllWith("");
    next_state.first_row = buffer.cursor.row;
    next_state.last_row = buffer.cursor.row;
}
