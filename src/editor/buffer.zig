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

const PieceTable = @import("piece_table.zig");
const utf8 = @import("../utf8.zig");
const globals = @import("../globals.zig");

const utils = @import("../utils.zig");

const global = globals.global;
const internal = globals.internal;

const Buffer = @This();

pub const Range = struct {
    start: u64,
    end: u64,
};

pub const State = enum {
    invalid,
    valid,
};

pub const MetaData = struct {
    file_path: []u8,
    file_type: []u8,
    file_last_mod_time: i128,
    dirty: bool,

    pub fn setFileType(metadata: *MetaData, new_ft: []const u8) !void {
        var file_type = try internal.allocator.alloc(u8, new_ft.len);
        std.mem.copy(u8, file_type, new_ft);
        internal.allocator.free(metadata.file_type);
        metadata.file_type = file_type;
    }

    pub fn setFilePath(metadata: *MetaData, new_fp: []const u8) !void {
        var file_path = try internal.allocator.alloc(u8, new_fp.len);
        std.mem.copy(u8, file_path, new_fp);
        internal.allocator.free(metadata.file_path);
        metadata.file_path = file_path;
    }
};

metadata: MetaData,
index: u32,
/// Represents the start index of the selection.
selection_start: u64 = 0,
/// The cursor index in the buffer. It also represents the end index of the selection.
cursor_index: u64,
/// The data structure holding every line in the buffer
lines: PieceTable,
state: State,

next_buffer: ?*Buffer = null,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8, buf: []const u8) !Buffer {
    const static = struct {
        var index: u32 = 0;
    };
    defer static.index += 1;
    var fp = try allocator.alloc(u8, file_path.len);
    std.mem.copy(u8, fp, file_path);

    var iter = std.mem.splitBackwards(u8, file_path, ".");
    const file_type = if (std.mem.containsAtLeast(u8, file_path, 1, ".")) iter.next().? else "";
    var ft = try allocator.alloc(u8, file_type.len);
    std.mem.copy(u8, ft, file_type);

    var metadata = MetaData{
        .file_path = fp,
        .file_type = ft,
        .file_last_mod_time = 0,
        .dirty = false,
    };

    var buffer = Buffer{
        .index = static.index,
        .metadata = metadata,
        .cursor_index = 0,
        .lines = try PieceTable.init(allocator, buf),
        .state = .valid,
    };

    try buffer.insureLastByteIsNewline();

    return buffer;
}

/// Deinits the buffer in the proper way using deinitAndDestroy() or deinitNoDestroy()
pub fn deinit(buffer: *Buffer) void {
    switch (buffer.state) {
        .valid => buffer.deinitAndDestroy(internal.allocator),
        .invalid => internal.allocator.destroy(buffer),
    }
}

/// Deinits the members of the buffer but does not destroy the buffer.
/// So pointers to this buffer are all valid through out the life time of the
/// program.
/// Sets state to State.invalid
pub fn deinitNoDestroy(buffer: *Buffer, allocator: std.mem.Allocator) void {
    buffer.lines.deinit();
    allocator.free(buffer.metadata.file_path);
    allocator.free(buffer.metadata.file_type);
    buffer.state = .invalid;
}

/// Deinits the members of the buffer and destroys the buffer.
/// Pointers to this buffer are all invalidated
pub fn deinitAndDestroy(buffer: *Buffer, allocator: std.mem.Allocator) void {
    buffer.deinitNoDestroy(allocator);
    allocator.destroy(buffer);
}

pub fn insertBeforeCursor(buffer: *Buffer, string: []const u8) !void {
    try buffer.lines.insert(buffer.cursor_index, string);
    buffer.cursor_index += string.len;
    buffer.metadata.dirty = true;
}

pub fn deleteBeforeCursor(buffer: *Buffer, characters_to_delete: u64) !void {
    if (buffer.cursor_index == 0) return;

    var i = buffer.cursor_index;
    var cont_bytes: u8 = 0;
    var characters: u64 = 0;

    { // Backward traverse the buffer while minding UTF-8
        while (characters != characters_to_delete) {
            const byte = buffer.lines.byteAt(i - 1);

            switch (utf8.byteType(byte)) {
                .start_byte => {
                    cont_bytes = 0;
                    characters += 1;
                    i -= 1;
                },
                .continue_byte => {
                    cont_bytes += 1;
                    i -= 1;
                },
            }

            if (cont_bytes > 3) unreachable;
        }
    }

    var old_index = buffer.cursor_index;
    var new_index = i;
    buffer.cursor_index = new_index;
    try buffer.lines.delete(buffer.cursor_index, old_index - new_index);

    buffer.metadata.dirty = true;

    try buffer.insureLastByteIsNewline();
}

pub fn deleteAfterCursor(buffer: *Buffer, characters_to_delete: u64) !void {
    var i = buffer.cursor_index;
    var cont_bytes: u8 = 0;
    var characters: u64 = 0;

    { // Forward traverse the buffer while minding UTF-8
        while (characters != characters_to_delete and i < buffer.lines.size) {
            const byte = buffer.lines.byteAt(i);

            switch (utf8.byteType(byte)) {
                .start_byte => {
                    cont_bytes = 0;
                    characters += 1;
                    i += unicode.utf8ByteSequenceLength(byte) catch unreachable;
                },
                .continue_byte => {
                    cont_bytes += 1;
                    i += 1;
                },
            }

            if (cont_bytes > 3) unreachable;
        }
    }

    var old_index = buffer.cursor_index;
    var new_index = i;
    try buffer.lines.delete(buffer.cursor_index, new_index - old_index);

    buffer.metadata.dirty = true;
    try buffer.insureLastByteIsNewline();
    buffer.cursor_index = min(buffer.cursor_index, buffer.lines.size - 1);
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    assert(start_row <= end_row);
    assert(end_row <= buffer.lines.newlines_count);

    const start_index = buffer.getIndex(start_row, 1);
    const end_index = if (end_row >= buffer.lines.newlines_count)
        buffer.lines.size + 1
    else
        buffer.getIndex(end_row + 1, 1);
    const num_to_delete = end_index - start_index;

    try buffer.lines.delete(start_index, num_to_delete);
    buffer.metadata.dirty = true;

    try buffer.insureLastByteIsNewline();
}

pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row)
        return error.InvalidRange;

    const start_index = buffer.getIndex(start_row, start_col);
    const end_index = if (end_row > buffer.lines.newlines_count)
        buffer.lines.size + 1
    else
        buffer.getIndex(end_row, end_col + 1);
    const num_to_delete = end_index - start_index;

    try buffer.lines.delete(start_index, num_to_delete);
    buffer.metadata.dirty = true;

    try buffer.insureLastByteIsNewline();
}

pub fn replaceAllWith(buffer: *Buffer, string: []const u8) !void {
    try buffer.clear();
    try buffer.lines.delete(0, 1); // Delete newline char
    try buffer.lines.insert(0, string);
    try buffer.insureLastByteIsNewline();
    buffer.metadata.dirty = true;
}

// TODO: this
// pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
// }

// TODO: Use fragmentOfLine() for the slice
pub fn countCodePointsAtRow(buffer: *Buffer, row: u64) usize {
    assert(row <= buffer.lines.newlines_count);
    const slice = buffer.getLine(internal.allocator, row) catch unreachable;
    defer internal.allocator.free(slice);
    return unicode.utf8CountCodepoints(slice) catch unreachable;
}

pub fn insureLastByteIsNewline(buffer: *Buffer) !void {
    if (buffer.lines.size == 0 or buffer.lines.byteAt(buffer.lines.size - 1) != '\n')
        try buffer.lines.insert(buffer.lines.size, "\n");
}

pub fn clear(buffer: *Buffer) !void {
    _ = buffer.lines.deinitTree(buffer.lines.pieces_root);
    var pt = buffer.lines;
    buffer.lines.pieces_root.* = .{
        .parent = null,
        .left = null,
        .right = null,

        .left_subtree_len = 0,
        .left_subtree_newlines_count = 0,

        .newlines_start = pt.add_newlines.items.len,
        .newlines_count = 0,

        .start = pt.add.items.len,
        .len = 0,
        .source = .add,
    };
    buffer.lines.size = 0;
    buffer.lines.newlines_count = 0;
    try buffer.insureLastByteIsNewline();
    buffer.metadata.dirty = true;

    buffer.moveAbsolute(1, 1);
}

pub fn getLine(buffer: *Buffer, allocator: std.mem.Allocator, row: u64) ![]u8 {
    assert(row <= buffer.lines.newlines_count);
    return buffer.lines.getLine(allocator, row - 1);
}

pub fn getLines(buffer: *Buffer, allocator: std.mem.Allocator, first_line: u64, last_line: u64) ![]u8 {
    assert(last_line >= first_line);
    assert(first_line > 0);
    assert(last_line <= buffer.lines.newlines_count);
    return buffer.lines.getLines(allocator, first_line - 1, last_line - 1);
}

/// Returns a copy of the entire buffer.
/// Caller owns memory.
pub fn getAllLines(buffer: *Buffer, allocator: std.mem.Allocator) ![]u8 {
    var array = try allocator.alloc(u8, buffer.lines.size);
    return buffer.lines.buildIntoArray(array);
}

pub fn getIndex(buffer: *Buffer, row: u64, col: u64) u64 {
    assert(row <= buffer.lines.newlines_count);
    assert(row > 0);
    var index: u64 = buffer.indexOfFirstByteAtRow(row);

    var char_count: u64 = 0;
    var i: u64 = 0;
    while (char_count < col - 1) {
        const byte = buffer.lines.byteAt(i + index);
        const byte_seq_len = unicode.utf8ByteSequenceLength(byte) catch 0;
        if (byte == '\n') {
            i += 1;
            break;
        } else if (byte_seq_len > 0) {
            char_count += 1;
            i += byte_seq_len;
        } else { // Continuation byte
            i += 1;
        }
    }

    var result = index + i;
    return result;
}

pub fn indexOfFirstByteAtRow(buffer: *Buffer, row: u64) u64 {
    // in the findNodeWithLine() call we subtract 2 from row because
    // rows in the buffer are 1-based but in buffer.lines they're 0-based so
    // we subtract 1 and because we use 0 as the index for row 1 because that's
    // the first byte of the first row we need to subtract another 1.
    return if (row == 1)
        0
    else
        buffer.lines.findNodeWithLine(row - 2).newline_index + 1;
}

pub fn getLineLength(buffer: *Buffer, row: u64) u64 {
    return buffer.getLinesLength(row, row);
}

pub fn getLinesLength(buffer: *Buffer, first_row: u64, last_row: u64) u64 {
    utils.assert(first_row <= last_row, "first_row must me <= last_row");
    var i = buffer.indexOfFirstByteAtRow(first_row);
    var j = buffer.indexOfFirstByteAtRow(last_row + 1);

    return j - i;
}

pub fn getRowAndCol(buffer: *Buffer, index_: u64) struct { row: u64, col: u64 } {
    var index = min(index_, buffer.lines.size);

    var row: u64 = 0;
    var newline_index: u64 = 0;
    while (row < buffer.lines.newlines_count) : (row += 1) {
        var ni = buffer.indexOfFirstByteAtRow(row + 1);
        if (ni <= index) newline_index = ni else break;
    }

    var col: u64 = 1;
    var i: u64 = newline_index;
    while (i < index) {
        const byte = buffer.lines.byteAt(i);
        const byte_seq_len = unicode.utf8ByteSequenceLength(byte) catch 0;
        if (byte == '\n') {
            break;
        } else if (byte_seq_len > 0) {
            col += 1;
            i += byte_seq_len;
        } else { // Continuation byte
            i += 1;
        }
    }

    return .{ .row = row, .col = col };
}

pub fn LineIterator(buffer: *Buffer, first_line: u64, last_line: u64) BufferIteratorType {
    const start = buffer.indexOfFirstByteAtRow(first_line);
    const end = buffer.indexOfFirstByteAtRow(last_line + 1);
    return .{
        .pt = &buffer.lines,
        .start = start,
        .end = end,
    };
}

pub fn BufferIterator(buffer: *Buffer, start: u64, end: u64) BufferIteratorType {
    return .{
        .pt = &buffer.lines,
        .start = start,
        .end = end,
    };
}

pub const BufferIteratorType = struct {
    const Self = @This();

    pt: *PieceTable,
    start: u64,
    end: u64,

    pub fn next(self: *Self) ?[]const u8 {
        if (self.start >= self.end) return null;
        const piece_info = self.pt.findNode(self.start);
        const string = piece_info.piece.content(self.pt)[piece_info.relative_index..];
        defer self.start += string.len;

        if (string.len + self.start < self.end) {
            return string;
        } else {
            const end = self.end - self.start;
            return string[0..end];
        }
    }
};

pub fn ReverseLineIterator(buffer: *Buffer, first_line: u64, last_line: u64) ReverseBufferIteratorType {
    const start = buffer.indexOfFirstByteAtRow(first_line);
    const end = buffer.indexOfFirstByteAtRow(last_line + 1);
    return .{
        .pt = &buffer.lines,
        .start = start,
        .end = std.math.min(buffer.lines.size - 1, end),
    };
}

pub fn ReverseBufferIterator(buffer: *Buffer, start: u64, end: u64) ReverseBufferIteratorType {
    return .{
        .pt = &buffer.lines,
        .start = start,
        .end = std.math.min(buffer.lines.size - 1, end),
    };
}

pub const ReverseBufferIteratorType = struct {
    const Self = @This();

    pt: *PieceTable,
    start: u64,
    end: u64,
    done: bool = false,

    pub fn next(self: *Self) ?[]const u8 {
        if (self.done) return null;
        if (self.end <= self.start or self.end == 0) self.done = true;

        const piece_info = self.pt.findNode(self.end);
        const content = piece_info.piece.content(self.pt);

        const node_start_abs_index = self.end - content[0..piece_info.relative_index].len;
        const end = piece_info.relative_index + 1;
        const start = if (utils.inRange(node_start_abs_index, self.start, self.end))
            0
        else
            self.start - node_start_abs_index;

        if (self.start == self.end) {
            self.done = true;
            return content[end - 1 .. end];
        } else {
            var string = content[start..end];

            const res = @subWithOverflow(self.end, string.len);
            if (res.@"1" == 1)
                self.end = 0
            else
                self.end = res.@"0";

            return string;
        }
    }
};

////////////////////////////////////////////////////////////////////////////////
// Cursor
////////////////////////////////////////////////////////////////////////////////

pub fn moveRelativeColumn(buffer: *Buffer, col_offset: i64, stop_before_newline: bool) void {
    if (col_offset == 0) return;
    if (buffer.cursor_index == 0 and col_offset <= 0) return;

    var i = buffer.cursor_index;
    if (col_offset > 0) {
        var characters: u64 = 0;
        while (characters != col_offset) {
            const byte = buffer.lines.byteAt(i);
            if (byte == '\n') {
                if (!stop_before_newline) i += 1;
                break;
            }

            const len = unicode.utf8ByteSequenceLength(byte) catch 0;
            if (len > 0) {
                i += len;
                characters += 1;
            } else { // Continuation byte
                i += 1;
            }
        }
    } else if (col_offset < 0) {
        var characters: u64 = 0;
        var cont_bytes: u8 = 0;
        while (characters != -col_offset) {
            const byte = buffer.lines.byteAt(if (i == 0) 0 else i - 1);
            if (byte == '\n') {
                i -= 1;
                break;
            }
            switch (utf8.byteType(byte)) {
                .start_byte => {
                    cont_bytes = 0;
                    characters += 1;
                    i -= 1;
                },
                .continue_byte => {
                    cont_bytes += 1;
                    i -= 1;
                },
            }

            if (cont_bytes > 3) unreachable;
        }
    }

    buffer.cursor_index = min(i, buffer.lines.size - 1);
}

pub fn moveRelativeRow(buffer: *Buffer, row_offset: i64) void {
    if (buffer.lines.size == 0) return;
    if (row_offset == 0) return;

    const cursor = buffer.getRowAndCol(buffer.cursor_index);

    var new_row = @intCast(i64, cursor.row) + row_offset;
    if (row_offset < 0) new_row = max(1, new_row) else new_row = min(new_row, buffer.lines.newlines_count);

    buffer.cursor_index = buffer.indexOfFirstByteAtRow(@intCast(u64, new_row));

    const old_col = cursor.col;
    moveRelativeColumn(buffer, @intCast(i64, old_col - 1), true);
}

pub fn moveAbsolute(buffer: *Buffer, row: u64, col: u64) void {
    if (row > buffer.lines.newlines_count) return;
    buffer.cursor_index = buffer.getIndex(row, col);
}

////////////////////////////////////////////////////////////////////////////////
// Cursor end
////////////////////////////////////////////////////////////////////////////////

pub fn setSelection(buffer: *Buffer, const_start: u64, const_end: u64) void {
    const end = std.math.min(const_end, buffer.lines.size);
    buffer.selection_start = const_start;
    buffer.cursor_index = end;
}

pub fn getSelection(buffer: *Buffer) Range {
    const start = std.math.min(buffer.selection_start, buffer.cursor_index);
    const end = std.math.max(buffer.selection_start, buffer.cursor_index);
    return .{ .start = start, .end = end };
}

pub fn resetSelection(buffer: *Buffer) void {
    buffer.selection_start = buffer.cursor_index;
}
