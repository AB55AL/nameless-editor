const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const Stack = std.ArrayList;
const unicode = std.unicode;
const assert = std.debug.assert;
const max = std.math.max;
const min = std.math.min;

const Cursor = @import("cursor.zig").Cursor;
const GapBuffer = @import("gap_buffer.zig");
const utf8 = @import("utf8.zig");
const globals = @import("../globals.zig");

const history = @import("history.zig");
const History = history.History;
const HistoryBufferState = history.HistoryBufferState;
const HistoryBufferStateResizeable = history.HistoryBufferStateResizeable;
const TypeOfChange = history.TypeOfChange;

const utils = @import("utils.zig");

const global = globals.global;
const internal = globals.internal;

pub const NUM_OF_SECTIONS = 32;

const Buffer = @This();

index: ?u32,
file_path: []u8,
cursor: Cursor,
/// The data structure holding every line in the buffer
lines: GapBuffer,
/// To make looking up lines quicker The buffer is spilt into multiple sections.
/// Each section starts after a newline char (except section 0 which always starts at the begging of the file).
/// The locations of these newline chars is stored here
sections: [NUM_OF_SECTIONS]usize,

history: History,
related_history_changes: Stack(HistoryBufferState),
previous_change: HistoryBufferStateResizeable,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8, buf: []const u8) !Buffer {
    const static = struct {
        var index: u32 = 0;
    };
    defer static.index += 1;
    var fp = try allocator.alloc(u8, file_path.len);
    std.mem.copy(u8, fp, file_path);

    var buffer = Buffer{
        .index = static.index,
        .file_path = fp,
        .cursor = .{ .row = 1, .col = 1 },
        .lines = try GapBuffer.init(allocator, buf),
        .history = History.init(allocator),
        .related_history_changes = Stack(HistoryBufferState).init(allocator),
        .previous_change = undefined,
        .sections = undefined,
    };

    buffer.insureLastByteIsNewline() catch unreachable;
    buffer.updateSections(1, 0);

    buffer.previous_change = .{
        .content = try GapBuffer.init(allocator, null),
        .index = 0,
        .type_of_change = TypeOfChange.insertion,
        .sections = buffer.sections,
        .lines_count = buffer.lines.count,
    };

    return buffer;
}

/// Deinits the members of the buffer but does not destroy the buffer.
/// So pointers to this buffer are all valid through out the life time of the
/// program.
/// Removes the buffer from the *global.buffers* array and places it into
/// the *internal.buffers_trashcan* to be freed just before exiting the program
/// The index of the buffer is set to `null` to signify that the buffer members
/// have been deinitialized
pub fn deinitAndTrash(buffer: *Buffer) void {
    buffer.deinitNoTrash();

    var index_in_global_array: usize = 0;
    for (global.buffers.items) |b, i| {
        if (b.index.? == buffer.index.?)
            index_in_global_array = i;
    }
    var removed_buffer = global.buffers.swapRemove(index_in_global_array);
    removed_buffer.index = null;
    internal.buffers_trashcan.append(removed_buffer) catch |err| {
        print("Couldn't append to internal.buffers_trashcan err={}\n", .{err});
    };
}

/// Deinits the members of the buffer but does not destroy the buffer.
/// So pointers to this buffer are all valid through out the life time of the
/// program.
/// Does **NOT** Place the buffer into the internal.buffers_trashcan.
/// Does **NOT** set the index to `null`
pub fn deinitNoTrash(buffer: *Buffer, allocator: std.mem.Allocator) void {
    buffer.lines.deinit();

    buffer.previous_change.content.deinit();
    while (buffer.related_history_changes.popOrNull()) |item|
        allocator.free(item.content);

    buffer.related_history_changes.deinit();
    buffer.history.deinit();

    allocator.free(buffer.file_path);
}

/// Deinits the members of the buffer and destroys the buffer.
/// Pointers to this buffer are all invalidated
pub fn deinitAndDestroy(buffer: *Buffer, allocator: std.mem.Allocator) void {
    buffer.deinitNoTrash(internal.allocator);
    allocator.destroy(buffer);
}

/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: u32, column: u32, string: []const u8) !void {
    assert(row <= buffer.lines.count + 1 and row > 0);

    if (builtin.mode == std.builtin.Mode.Debug) if (!unicode.utf8ValidateSlice(string)) unreachable;

    var index = if (row <= buffer.lines.count)
        buffer.getIndex(row, column)
    else
        buffer.lines.length();

    buffer.history.emptyRedoStack();
    try buffer.mergeOrPushHistoryChange(&buffer.previous_change, .{
        .content = string,
        .index = index,
        .type_of_change = TypeOfChange.insertion,
        .sections = buffer.sections,
        .lines_count = buffer.lines.count,
    });

    buffer.lines.moveGapPosAbsolute(index);
    try buffer.lines.insert(string);

    var num_of_newlines: u32 = utils.countChar(string, '\n');
    const old_nl_count = buffer.lines.count;
    try insureLastByteIsNewline(buffer);
    buffer.lines.count += num_of_newlines;

    buffer.adjustSections(row, num_of_newlines, @intCast(isize, string.len), old_nl_count);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
/// If end_column is greater than the number of characters in the line then
/// delete() would delete to the end of line
pub fn delete(buffer: *Buffer, row: u32, start_column: u32, end_column: u32) !void {
    assert(row > 0 and row <= buffer.lines.count);

    try insureLastByteIsNewline(buffer);

    const index = buffer.getIndex(row, start_column);
    const slice = buffer.getLine(row);
    const end = min(end_column - 1, unicode.utf8CountCodepoints(slice) catch unreachable);
    const substring = utf8.substringOfUTF8Sequence(slice, start_column, end) catch unreachable;

    buffer.history.emptyRedoStack();
    try buffer.mergeOrPushHistoryChange(&buffer.previous_change, .{
        .content = substring,
        .index = index,
        .type_of_change = TypeOfChange.deletion,
        .sections = buffer.sections,
        .lines_count = buffer.lines.count,
    });

    buffer.lines.moveGapPosAbsolute(index);
    buffer.lines.delete(substring.len);

    var num_of_newlines: u32 = utils.countChar(substring, '\n');
    const old_nl_count = buffer.lines.count;
    buffer.lines.count -= num_of_newlines;
    try insureLastByteIsNewline(buffer);
    buffer.adjustSections(row, num_of_newlines, -@intCast(isize, substring.len), old_nl_count);

    // make sure the cursor.row is never on a row that doesn't exists
    if (utils.getNewline(buffer.lines.slice(0, buffer.lines.length()), buffer.cursor.row) == null)
        Cursor.moveRelative(buffer, -1, 0);
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    assert(start_row <= end_row);
    assert(end_row <= buffer.lines.count);

    const index = buffer.getIndex(start_row, 1);
    var to: usize = 0;
    if (end_row < buffer.lines.count) {
        to = utils.getNewline(
            buffer.lines.slice(index, buffer.lines.length()),
            end_row - start_row + 1,
        ).? + index + 1;
    } else {
        to = buffer.lines.length();
    }

    const substring = buffer.lines.slice(index, to);

    buffer.history.emptyRedoStack();
    try buffer.mergeOrPushHistoryChange(&buffer.previous_change, .{
        .content = substring,
        .index = index,
        .type_of_change = TypeOfChange.deletion,
        .sections = buffer.sections,
        .lines_count = buffer.lines.count,
    });

    try insureLastByteIsNewline(buffer);

    buffer.lines.moveGapPosAbsolute(index);
    buffer.lines.delete(substring.len);

    var num_of_newlines: u32 = end_row - start_row + 1;
    const old_nl_count = buffer.lines.count;
    buffer.lines.count -= num_of_newlines;
    buffer.adjustSections(start_row, num_of_newlines, -@intCast(isize, substring.len), old_nl_count);

    try insureLastByteIsNewline(buffer);

    // make sure the cursor.row is never on a row that doesn't exists
    if (utils.getNewline(buffer.lines.slice(0, buffer.lines.length()), buffer.cursor.row) == null)
        Cursor.moveAbsolute(buffer, start_row - 1, 1);
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row)
        return error.InvalidRange;

    try insureLastByteIsNewline(buffer);

    if (start_row == end_row) {
        try delete(buffer, start_row, start_col, end_col + 1);
    } else if (start_row == end_row - 1) {
        try delete(buffer, end_row, 1, end_col + 1);
        var line = buffer.getLine(start_row);
        try delete(buffer, start_row, start_col, @intCast(u32, line.len + 1));
    } else {
        try delete(buffer, end_row, 1, end_col + 1);

        try deleteRows(buffer, start_row + 1, end_row - 1);

        var line = buffer.getLine(start_row);
        try delete(buffer, start_row, start_col, @intCast(u32, line.len) + 1);
    }

    try insureLastByteIsNewline(buffer);
}

pub fn replaceAllWith(buffer: *Buffer, string: []const u8) !void {
    try buffer.deleteRows(1, buffer.lines.count);
    // Delete the insured newline
    buffer.lines.moveGapPosAbsolute(0);
    buffer.lines.delete(1);
    try buffer.insert(1, 1, string);
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

pub fn countCodePointsAtRow(buffer: *Buffer, row: u32) usize {
    assert(row <= buffer.lines.count);
    const slice = buffer.getLine(row);
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
        try buffer.lines.append("\n");
        buffer.lines.count += 1;
    }
}

pub fn clear(buffer: *Buffer) !void {
    try history.updateRelatedHistoryChanges(buffer);
    try buffer.previous_change.content.replaceAllWith(buffer.lines.slice(0, buffer.lines.length()));
    buffer.previous_change.index = 1;
    buffer.previous_change.type_of_change = TypeOfChange.deletion;

    buffer.lines.replaceAllWith("") catch unreachable;
    buffer.insureLastByteIsNewline() catch unreachable;
}

pub fn getLine(buffer: *Buffer, row: u32) []const u8 {
    assert(row <= buffer.lines.count);
    const from = buffer.getIndex(row, 1);
    const to = utils.getNewline(buffer.lines.slice(from, buffer.lines.length()), 1).? + from + 1;
    return buffer.lines.slice(from, to);
}

pub fn getLines(buffer: *Buffer, first_line: u32, second_line: u32) []const u8 {
    assert(second_line >= first_line);
    assert(second_line <= buffer.lines.count);

    const from = buffer.getIndex(first_line, 1);
    const to = buffer.getIndex(second_line, null);
    return buffer.lines.slice(from, to + 1);
}

fn getNewline(string: []const u8, start_index: usize, index: usize) ?usize {
    var count: u32 = 0;
    var i: usize = 0;
    while (i + start_index < string.len) : (i += 1) {
        const c = string[i + start_index];
        if (c == '\n') {
            count += 1;
            if (count == index)
                return i + start_index;
        }
    }

    return i + start_index;
}

fn getIndex(buffer: *Buffer, row: u32, col: ?u32) usize {
    assert(row <= buffer.lines.count);

    if (buffer.lines.length() == 1) return 0;

    const nl_num = buffer.lines.count;
    var sections = buffer.sections;

    var lines_per_section = @floor(@intToFloat(f32, nl_num) / NUM_OF_SECTIONS);
    if (lines_per_section == 0) lines_per_section = 1;
    var section = @floatToInt(u32, @ceil(@intToFloat(f32, row) / lines_per_section) - 1.0);
    section = min(section, NUM_OF_SECTIONS - 1);

    const start_of_section = if (section == 0) 0 else sections[section] + 1;
    var line_offset_in_section = row - (section * @floatToInt(u32, lines_per_section));
    const first_line_in_section = row == (section * @floatToInt(u32, lines_per_section) + 1);

    var index: usize = 0;
    if (first_line_in_section) {
        index = start_of_section;
    } else {
        index = getNewline(buffer.lines.slice(0, buffer.lines.length()), start_of_section, line_offset_in_section - 1).? + 1;
    }

    const buffer_len = buffer.lines.length();
    index = min(index, if (buffer_len == 0) 0 else buffer_len - 1);
    if (col) |c|
        index += utf8.firstByteOfCodeUnitUpToNewline(buffer.lines.slice(index, buffer.lines.length()), c)
    else
        index += getNewline(buffer.lines.slice(index, buffer.lines.length()), 0, 1).?;

    return index;
}

fn adjustSections(buffer: *Buffer, row: u32, num_of_newlines: u32, substring_len: isize, old_nl_count: u32) void {
    var sections = &buffer.sections;

    var new_lines_per_section = @floor(@intToFloat(f32, buffer.lines.count) / NUM_OF_SECTIONS);
    if (new_lines_per_section == 0) new_lines_per_section = 1;

    var lines_per_section = @floor(@intToFloat(f32, old_nl_count) / NUM_OF_SECTIONS);
    if (lines_per_section == 0) lines_per_section = 1;
    var first_modified_section = @floatToInt(u32, @ceil(@intToFloat(f32, row) / lines_per_section) - 1.0);
    first_modified_section = min(first_modified_section, NUM_OF_SECTIONS - 1);

    if (first_modified_section >= NUM_OF_SECTIONS - 1) return;

    if (num_of_newlines == 0) {
        var i = if (first_modified_section == 0) 1 else first_modified_section + 1;
        while (i < sections.len) : (i += 1) {
            var new_index = @intCast(isize, sections[i]) + substring_len;
            new_index = max(0, new_index);
            sections[i] = @intCast(usize, new_index);
        }
    } else if (new_lines_per_section != lines_per_section) {
        buffer.updateSections(1, 0);
    } else {
        // TODO: update affected sections instead of all of them
        buffer.updateSections(1, 0);
    }
}

fn printSection(buffer: *Buffer, row: u32) void {
    var lines_per_section = @floor(@intToFloat(f32, buffer.lines.count) / NUM_OF_SECTIONS);
    if (lines_per_section == 0) lines_per_section = 1;
    var section = @floatToInt(u32, @ceil(@intToFloat(f32, row) / lines_per_section) - 1.0);
    section = min(section, NUM_OF_SECTIONS - 1);

    print("{}\n", .{section});
}

fn updateSections(buffer: *Buffer, start_section: usize, start_index: usize) void {
    if (buffer.lines.length() == 0) return;
    var lines_per_section = @floatToInt(u32, @floor(@intToFloat(f32, buffer.lines.count) / NUM_OF_SECTIONS));
    if (lines_per_section == 0) lines_per_section = 1;

    var sections = &buffer.sections;
    sections[0] = 0;

    var index: usize = if (start_section == 0) 1 else start_section;
    var nl_count: u32 = 0;
    var nl: u32 = lines_per_section;
    const start_i = min(buffer.lines.length() - 1, start_index);
    const slice = buffer.lines.slice(start_i, buffer.lines.length());
    @setRuntimeSafety(false);
    // TODO: skip utf8 continuation bytes
    for (slice) |b, i| {
        if (b == '\n') {
            nl_count += 1;
            if (nl_count == nl) {
                nl += lines_per_section;
                sections[index] = i;
                index += 1;
            }
            if (index >= NUM_OF_SECTIONS) break;
        }
    }

    if (lines_per_section == 1 and buffer.lines.count < NUM_OF_SECTIONS) {
        var i: usize = buffer.lines.count;
        while (i < sections.len) : (i += 1)
            sections[i] = sections[buffer.lines.count];
    }
}
