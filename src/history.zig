const std = @import("std");
const print = std.debug.print;
const Stack = std.ArrayList;
const ArrayList = std.ArrayList;

const Buffer = @import("buffer.zig");
const Cursor = @import("cursor.zig");
const GapBuffer = @import("gap_buffer.zig");

const GlobalInternal = @import("global_types.zig").GlobalInternal;
extern var internal: GlobalInternal;

pub const TypeOfChange = enum(u1) {
    insertion,
    deletion,
};

pub const HistoryBufferState = struct {
    content: []const u8,
    index: usize,
    type_of_change: TypeOfChange,
};

pub const HistoryBufferStateResizeable = struct {
    content: GapBuffer,
    index: usize,
    type_of_change: TypeOfChange,
};

pub const History = struct {
    stack: Stack([]const HistoryBufferState),
    redo_stack: Stack([]const HistoryBufferState),

    pub fn init() History {
        return History{
            .stack = Stack([]const HistoryBufferState).init(internal.allocator),
            .redo_stack = Stack([]const HistoryBufferState).init(internal.allocator),
        };
    }

    pub fn deinit(history: *History) void {
        const free = internal.allocator.free;

        while (history.stack.popOrNull()) |buffer_states| {
            for (buffer_states) |state|
                free(state.content);
            free(buffer_states);
        }

        while (history.redo_stack.popOrNull()) |buffer_states| {
            for (buffer_states) |state|
                free(state.content);
            free(buffer_states);
        }

        history.redo_stack.deinit();
        history.stack.deinit();
    }

    pub fn emptyRedoStack(history: *History) void {
        const free = internal.allocator.free;
        while (history.redo_stack.popOrNull()) |buffer_states|
            for (buffer_states) |state|
                free(state.content);
    }
};

pub fn undo(buffer: *Buffer) !void {
    try commitHistoryChanges(buffer);
    if (buffer.history.stack.items.len == 0) return;

    const stack = &buffer.history.stack;

    var changes = stack.pop();
    if (changes.len == 0) return;

    var i: usize = changes.len;
    while (i > 0) {
        i -= 1;
        const change: HistoryBufferState = changes[i];
        switch (change.type_of_change) {
            TypeOfChange.insertion => {
                buffer.lines.deleteAfter(
                    change.index,
                    change.content.len,
                );
                try buffer.insureLastByteIsNewline();
            },
            TypeOfChange.deletion => {
                // Delete the newline char so that it doesn't stick around after undoing
                // an entire buffer deletion
                if (buffer.lines.length() == 1) {
                    buffer.lines.deleteAfter(0, 1);
                }
                try buffer.lines.insertAt(
                    change.index,
                    change.content,
                );
            },
        }
    }

    try buffer.history.redo_stack.append(changes);
}

pub fn redo(buffer: *Buffer) !void {
    if (buffer.history.redo_stack.items.len == 0) return;

    const redo_stack = &buffer.history.redo_stack;
    var changes = redo_stack.pop();
    if (changes.len == 0) return;

    for (changes) |change| {
        switch (change.type_of_change) {
            TypeOfChange.insertion => {
                try buffer.lines.insertAt(
                    change.index,
                    change.content,
                );
            },
            TypeOfChange.deletion => {
                buffer.lines.deleteAfter(
                    change.index,
                    change.content.len,
                );
                try buffer.insureLastByteIsNewline();
            },
        }
    }

    try buffer.history.stack.append(changes);
}

pub fn commitHistoryChanges(buffer: *Buffer) !void {
    try updateRelatedHistoryChanges(buffer);
    if (buffer.related_history_changes.items.len == 0) return;
    try buffer.history.stack.append(buffer.related_history_changes.toOwnedSlice());
}

pub fn updateRelatedHistoryChanges(buffer: *Buffer) !void {
    var pc = &buffer.previous_change;

    if (pc.content.isEmpty()) return;

    try buffer.related_history_changes.append(.{
        .content = try pc.content.copy(),
        .index = pc.index,
        .type_of_change = pc.type_of_change,
    });
    pc.content.replaceAllWith("") catch unreachable;
    pc.index = 0;
}
