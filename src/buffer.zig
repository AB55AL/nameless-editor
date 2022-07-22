const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const Stack = std.ArrayList;
const unicode = std.unicode;

const Cursor = @import("cursor.zig").Cursor;
const GapBuffer = @import("gap_buffer.zig");
const utf8 = @import("utf8.zig");

const history = @import("history.zig");
const History = history.History;
const HistoryBufferState = history.HistoryBufferState;
const HistoryBufferStateResizeable = history.HistoryBufferStateResizeable;
const TypeOfChange = history.TypeOfChange;

const utils = @import("utils.zig");

extern var global_allocator: std.mem.Allocator;

const Buffer = @This();

file_path: []u8,
size: usize,
cursor: Cursor,
/// The data structure holding every line in the buffer
lines: GapBuffer,

history: History,
related_history_changes: Stack(HistoryBufferState),
previous_change: HistoryBufferStateResizeable,

pub fn init(file_path: []const u8, buf: []const u8) !Buffer {
    var lines = try GapBuffer.init(global_allocator, buf);
    var cursor = .{ .row = 1, .col = 1 };
    var fp = try global_allocator.alloc(u8, file_path.len);
    std.mem.copy(u8, fp, file_path);

    var related_history_changes = Stack(HistoryBufferState).init(global_allocator);

    var size = buf.len;
    var buffer_history = History.init();
    var previous_change = .{
        .content = try GapBuffer.init(global_allocator, null),
        .index = 0,
        .type_of_change = TypeOfChange.insertion,
    };
    return Buffer{
        .file_path = fp,
        .size = size,
        .cursor = cursor,
        .lines = lines,
        .history = buffer_history,
        .related_history_changes = related_history_changes,
        .previous_change = previous_change,
    };
}

pub fn deinit(buffer: *Buffer) void {
    buffer.lines.deinit();

    buffer.previous_change.content.deinit();
    while (buffer.related_history_changes.popOrNull()) |item|
        global_allocator.free(item.content);

    buffer.related_history_changes.deinit();
    buffer.history.deinit();

    global_allocator.free(buffer.file_path);
}
/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: u32, column: u32, string: []const u8) !void {
    if (builtin.mode == std.builtin.Mode.Debug) if (!unicode.utf8ValidateSlice(string)) unreachable;

    var num_of_newlines: u32 = utils.countChar(buffer.lines.sliceOfContent(), '\n');
    if (row <= 0 or row > num_of_newlines)
        return error.IndexOutOfBounds;

    const index = utils.getIndex(buffer.lines.sliceOfContent(), row, column);
    buffer.history.emptyRedoStack();
    try buffer.mergeOrPushHistoryChange(&buffer.previous_change, .{
        .content = string,
        .index = index,
        .type_of_change = TypeOfChange.insertion,
    });

    buffer.lines.moveGapPosAbsolute(index);
    try buffer.lines.insert(string);

    try insureLastByteIsNewline(buffer);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
/// If end_column is greater than the number of characters in the line then
/// delete() would delete to the end of line
pub fn delete(buffer: *Buffer, row: u32, start_column: u32, end_column: u32) !void {
    if (row <= 0 or row > buffer.lines.length()) {
        print("delete(): range out of bounds\n", .{});
        return error.IndexOutOfBounds;
    }

    try insureLastByteIsNewline(buffer);

    const index = utils.getIndex(buffer.lines.sliceOfContent(), row, start_column);
    const slice = utils.getLine(buffer.lines.sliceOfContent(), row);
    const substring = utf8.substringOfUTF8Sequence(slice, start_column, end_column - 1) catch unreachable;

    buffer.history.emptyRedoStack();
    try buffer.mergeOrPushHistoryChange(&buffer.previous_change, .{
        .content = substring,
        .index = index,
        .type_of_change = TypeOfChange.deletion,
    });

    buffer.lines.moveGapPosAbsolute(index);
    buffer.lines.delete(substring.len);

    try insureLastByteIsNewline(buffer);
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    if (start_row > end_row)
        return error.InvalidRange;

    var from = utils.getNewline(buffer.lines.sliceOfContent(), start_row - 1).?;
    var to = utils.getNewline(buffer.lines.sliceOfContent(), end_row) orelse buffer.lines.length();

    const f = if (from == 0) 0 else from + 1;
    const substring = buffer.lines.sliceOfContent()[f .. to + 1];

    buffer.history.emptyRedoStack();
    try buffer.mergeOrPushHistoryChange(&buffer.previous_change, .{
        .content = substring,
        .index = f,
        .type_of_change = TypeOfChange.deletion,
    });

    try insureLastByteIsNewline(buffer);

    if (start_row == 1) to += 1; // FIXME: Find out why this is needed

    buffer.lines.moveGapPosAbsolute(from);
    buffer.lines.delete(to - from);

    try insureLastByteIsNewline(buffer);
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row)
        return error.InvalidRange;

    try insureLastByteIsNewline(buffer);

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
        try delete(buffer, start_row, start_col, @intCast(u32, line.len) + 1);
    }

    try insureLastByteIsNewline(buffer);
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
    if (buffer.lines.isEmpty()) return 0;
    if (row > utils.countChar(buffer.lines.sliceOfContent(), '\n')) {
        unreachable;
    }

    const slice = utils.getLine(buffer.lines.sliceOfContent(), row);
    return unicode.utf8CountCodepoints(slice) catch unreachable;
}

fn mergeOrPushHistoryChange(
    buffer: *Buffer,
    previous_change: *HistoryBufferStateResizeable,
    upcoming_change: HistoryBufferState,
) !void {
    var pc = previous_change;
    var uc = upcoming_change;

    if (pc.content.isEmpty()) {
        try pc.content.replaceAllWith(uc.content);
        pc.index = uc.index;
        pc.type_of_change = uc.type_of_change;
    } else if (!changesAreRelated(pc, uc)) {
        try history.updateRelatedHistoryChanges(buffer);
        try pc.content.replaceAllWith(uc.content);
        pc.index = uc.index;
        pc.type_of_change = uc.type_of_change;
    } else if (changesCanBeMerged(pc, uc)) {
        try mergeChanges(pc, uc);
    } else {
        try history.updateRelatedHistoryChanges(buffer);
        try pc.content.replaceAllWith(uc.content);
        pc.index = uc.index;
        pc.type_of_change = uc.type_of_change;
    }
}

fn changesCanBeMerged(
    previous_change: *HistoryBufferStateResizeable,
    upcoming_change: HistoryBufferState,
) bool {
    var pc = previous_change;
    var uc = upcoming_change;

    if (!changesAreRelated(pc, uc)) return false;

    var same_type = pc.type_of_change == uc.type_of_change;
    if (same_type and changesAreRelated(pc, uc)) return true;

    const correction_type =
        pc.type_of_change == TypeOfChange.insertion and
        uc.type_of_change == TypeOfChange.deletion;

    if (correction_type) {
        var i: i64 = @intCast(i64, uc.index) - @intCast(i64, pc.index);
        if (i == 0) {
            return true;
        } else if (i - 1 < 0) {
            return false;
        } else if (utils.inRange(
            usize,
            uc.index,
            pc.index,
            pc.index + pc.content.length() - 1,
        )) return true;
    }

    return false;
}

fn changesAreRelated(
    previous_change: *HistoryBufferStateResizeable,
    upcoming_change: HistoryBufferState,
) bool {
    var pc = previous_change;
    var uc = upcoming_change;
    var index = if (pc.index == 0) 0 else pc.index - 1;

    return utils.inRange(
        usize,
        uc.index,
        index,
        pc.index + pc.content.length(),
    );
}

fn mergeChanges(
    previous_change: *HistoryBufferStateResizeable,
    upcoming_change: HistoryBufferState,
) !void {
    var pc = previous_change;
    var uc = upcoming_change;
    var pc_index = if (pc.index == 0) 0 else pc.index - 1; // avoid integer underflows

    var same_type = pc.type_of_change == uc.type_of_change;
    var correction_type =
        pc.type_of_change == TypeOfChange.insertion and
        uc.type_of_change == TypeOfChange.deletion;

    if (same_type) {
        if (uc.index == pc_index) {
            try pc.content.prepend(uc.content);
            pc.index = if (pc.index == 0) 0 else pc.index - 1;
        } else if (uc.type_of_change == TypeOfChange.deletion) {
            try pc.content.append(uc.content);
        } else if (uc.type_of_change == TypeOfChange.insertion) {
            const i = uc.index - pc.index;
            try pc.content.insertAt(i, uc.content);
        }
    } else if (correction_type and uc.index - pc_index >= 0 and
        utils.inRange(usize, uc.index, pc.index, pc.index + pc.content.length() - 1))
    {
        previous_change.content.deleteAfter(uc.index - pc_index, uc.content.len);
        if (uc.index - pc.index == 0) {
            previous_change.content.replaceAllWith("") catch unreachable;
            previous_change.index = uc.index;
            previous_change.type_of_change = uc.type_of_change;
        }
    } else {
        return error.ChangesCannotBeMerged;
    }
}

pub fn insureLastByteIsNewline(buffer: *Buffer) !void {
    buffer.lines.moveGapPosRelative(-1);
    if (buffer.lines.content[buffer.lines.content.len - 1] != '\n' or
        buffer.lines.length() == 0)
    {
        buffer.lines.moveGapPosAbsolute(buffer.lines.length());
        try buffer.lines.insert("\n");
    }
}
