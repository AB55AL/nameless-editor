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

pub const PieceTable = @import("piece_table.zig");
const utf8 = @import("../utf8.zig");
const NaryTree = @import("../nary.zig").NaryTree;
const utils = @import("../utils.zig");

const HistoryTree = NaryTree(HistoryInfo);

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
    dirty: bool = false,
    history_dirty: bool = false,

    pub fn setFileType(metadata: *MetaData, allocator: std.mem.Allocator, new_ft: []const u8) !void {
        var file_type = try allocator.alloc(u8, new_ft.len);
        std.mem.copy(u8, file_type, new_ft);
        allocator.free(metadata.file_type);
        metadata.file_type = file_type;
    }

    pub fn setFilePath(metadata: *MetaData, allocator: std.mem.Allocator, new_fp: []const u8) !void {
        var file_path = try allocator.alloc(u8, new_fp.len);
        std.mem.copy(u8, file_path, new_fp);
        allocator.free(metadata.file_path);
        metadata.file_path = file_path;
    }

    pub fn setDirty(metadata: *MetaData) void {
        metadata.dirty = true;
        metadata.history_dirty = true;
    }
};

pub const HistoryInfo = struct {
    cursor_index: u64,
    pieces: []const PieceTable.PieceNode.Info,
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
allocator: std.mem.Allocator,

history: HistoryTree = HistoryTree{},
history_node: ?*HistoryTree.Node = null,

next_buffer: ?*Buffer = null,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8, buf: []const u8) !Buffer {
    const static = struct {
        var index: u32 = 0;
    };
    defer static.index += 1;
    var fp = try allocator.alloc(u8, file_path.len);
    std.mem.copy(u8, fp, file_path);

    var iter = std.mem.splitBackwards(u8, file_path, ".");
    const file_type = iter.next() orelse "";
    var ft = try allocator.alloc(u8, file_type.len);
    std.mem.copy(u8, ft, file_type);

    var metadata = MetaData{
        .file_path = fp,
        .file_type = ft,
        .file_last_mod_time = 0,
        .dirty = false,
        .history_dirty = false,
    };

    var buffer = Buffer{
        .index = static.index,
        .metadata = metadata,
        .cursor_index = 0,
        .lines = try PieceTable.init(allocator, buf),
        .state = .valid,
        .allocator = allocator,
    };

    try buffer.insureLastByteIsNewline();
    try buffer.pushHistory(true);

    return buffer;
}

/// Deinits the buffer in the proper way using deinitAndDestroy() or deinitNoDestroy()
pub fn deinit(buffer: *Buffer) void {
    switch (buffer.state) {
        .valid => buffer.deinitAndDestroy(),
        .invalid => buffer.allocator.destroy(buffer),
    }
}

/// Deinits the members of the buffer but does not destroy the buffer.
/// So pointers to this buffer are all valid through out the life time of the
/// program.
/// Sets state to State.invalid
pub fn deinitNoDestroy(buffer: *Buffer) void {
    buffer.lines.deinit(buffer.allocator);
    buffer.allocator.free(buffer.metadata.file_path);
    buffer.allocator.free(buffer.metadata.file_type);
    buffer.state = .invalid;

    buffer.history.deinitTree(buffer.allocator, deinitHistory);
}

fn deinitHistory(allocator: std.mem.Allocator, node_data: *HistoryInfo) void {
    allocator.free(node_data.pieces);
}

/// Deinits the members of the buffer and destroys the buffer.
/// Pointers to this buffer are all invalidated
pub fn deinitAndDestroy(buffer: *Buffer) void {
    buffer.deinitNoDestroy();
    buffer.allocator.destroy(buffer);
}

pub fn insertAt(buffer: *Buffer, index: u64, string: []const u8) !void {
    try buffer.validateInsertionPoint(index);
    try buffer.lines.insert(buffer.allocator, index, string);
    buffer.metadata.setDirty();
    try buffer.insureLastByteIsNewline();
}

/// End inclusive
pub fn deleteRange(buffer: *Buffer, start: u64, end: u64) !void {
    const s = std.math.min(start, end);
    const e = std.math.max(start, end);

    try buffer.validateRange(s, e);
    try buffer.lines.delete(buffer.allocator, s, e);

    buffer.metadata.setDirty();
    try buffer.insureLastByteIsNewline();
}

pub fn replaceAllWith(buffer: *Buffer, string: []const u8) !void {
    var root = PieceTable.PieceNode.deinitTree(buffer.lines.tree.root, buffer.allocator);
    if (root) |r| buffer.allocator.destroy(r);
    buffer.lines.tree = .{};

    try buffer.lines.insert(buffer.allocator, 0, string);
    try buffer.insureLastByteIsNewline();
    buffer.metadata.setDirty();
}

pub fn clear(buffer: *Buffer) !void {
    var root = PieceTable.PieceNode.deinitTree(buffer.lines.tree.root, buffer.allocator);
    if (root) |r| buffer.allocator.destroy(r);

    buffer.lines.tree = .{};
    try buffer.insureLastByteIsNewline();
    buffer.metadata.setDirty();

    buffer.cursor_index = 0;
}

////////////////////////////////////////////////////////////////////////////////
// Convenience insertion and deletion functions
////////////////////////////////////////////////////////////////////////////////
pub fn insertBeforeCursor(buffer: *Buffer, string: []const u8) !void {
    try buffer.insertAt(buffer.cursor_index, string);
    buffer.cursor_index += string.len;
}

pub fn deleteBeforeCursor(buffer: *Buffer, characters_to_delete: u64) !void {
    if (buffer.cursor_index == 0) return;

    var characters: u64 = 0;
    var iter = ReverseBufferIterator.init(buffer, 0, buffer.cursor_index - 1);
    var bytes_to_delete: u64 = 0;
    outer_loop: while (iter.next()) |string| {
        var view = utf8.ReverseUtf8View(string);
        while (view.prevSlice()) |slice| {
            characters += 1;
            bytes_to_delete += slice.len;
            if (characters == characters_to_delete) break :outer_loop;
        }
    }

    buffer.cursor_index -|= bytes_to_delete;
    const delete_to = buffer.cursor_index + bytes_to_delete -| 1;

    try buffer.deleteRange(buffer.cursor_index, delete_to);
}

pub fn deleteAfterCursor(buffer: *Buffer, characters_to_delete: u64) !void {
    var i = buffer.cursor_index;
    var characters: u64 = 0;

    var iter = BufferIterator.init(buffer, i, buffer.size());
    while (iter.next()) |string| {
        if (characters == characters_to_delete) break;
        var view = unicode.Utf8View.initUnchecked(string).iterator();
        while (view.nextCodepointSlice()) |slice| {
            characters += 1;
            i += slice.len;
            if (characters == characters_to_delete) break;
        }
    }

    try buffer.deleteRange(buffer.cursor_index, i - 1);
    buffer.cursor_index = min(buffer.cursor_index, buffer.size() - 1);
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    assert(start_row <= end_row);
    assert(end_row <= buffer.lineCount());

    const start_index = buffer.getIndex(start_row, 1);
    const end_index = if (end_row >= buffer.lineCount())
        buffer.size() + 1
    else
        buffer.getIndex(end_row + 1, 1) -| 1;

    try buffer.deleteRange(start_index, end_index);
}

pub fn deleteRangeRC(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row)
        return error.InvalidRange;

    const start_index = buffer.getIndex(start_row, start_col);
    const end_index = if (end_row > buffer.lineCount())
        buffer.size() + 1
    else
        buffer.getIndex(end_row, end_col + 1) -| 1;

    try buffer.deleteRange(start_index, end_index);
}

// TODO: this
// pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
// }

pub fn validateInsertionPoint(buffer: *Buffer, index: u64) !void {
    const i = std.math.min(index, buffer.size() -| 1);
    if (utf8.byteType(buffer.lines.byteAt(i)) == .continue_byte)
        return error.invalidInsertionPoint;
}

pub fn validateRange(buffer: *Buffer, start: u64, end: u64) !void {
    const s = std.math.min(start, buffer.size() -| 1);
    const e = std.math.min(end + 1, buffer.size() -| 1);

    if (utf8.byteType(buffer.lines.byteAt(s)) == .continue_byte)
        return error.invalidRange;

    if (e == buffer.size() - 1)
        return
    else if (utf8.byteType(buffer.lines.byteAt(e)) == .continue_byte)
        return error.invalidRange;
}

pub fn countCodePointsAtRow(buffer: *Buffer, row: u64) u64 {
    assert(row <= buffer.lineCount());
    var count: u64 = 0;
    var iter = LineIterator.init(buffer, row, row);
    while (iter.next()) |slice|
        count += unicode.utf8CountCodepoints(slice) catch unreachable;

    return count;
}

pub fn insureLastByteIsNewline(buffer: *Buffer) !void {
    if (buffer.size() == 0 or buffer.lines.byteAt(buffer.size() - 1) != '\n') {
        // std.debug.print("INSERTED NL\t", .{});
        try buffer.lines.insert(buffer.allocator, buffer.size(), "\n");
    }
}

pub fn lineSize(buffer: *Buffer, line: u64) u64 {
    return buffer.indexOfLastByteAtRow(line) - buffer.indexOfFirstByteAtRow(line) + 1;
}

pub fn lineRangeSize(buffer: *Buffer, start_line: u64, end_line: u64) u64 {
    return buffer.indexOfLastByteAtRow(end_line) - buffer.indexOfFirstByteAtRow(start_line) + 1;
}

pub fn getLine(buffer: *Buffer, allocator: std.mem.Allocator, row: u64) ![]u8 {
    assert(row <= buffer.lineCount());

    var line = try allocator.alloc(u8, buffer.lineSize(row));
    var iter = LineIterator.init(buffer, row, row);
    var start: u64 = 0;
    while (iter.next()) |slice| {
        std.mem.copy(u8, line[start..], slice);
        start += slice.len;
    }

    return line;
}

pub fn getLines(buffer: *Buffer, allocator: std.mem.Allocator, first_line: u64, last_line: u64) ![]u8 {
    assert(last_line >= first_line);
    assert(first_line > 0);
    assert(last_line <= buffer.lineCount());

    var lines = try allocator.alloc(u8, buffer.lineRangeSize(first_line, last_line));
    var iter = LineIterator.init(buffer, first_line, last_line);
    var start: u64 = 0;
    while (iter.next()) |slice| {
        std.mem.copy(u8, lines[start..], slice);
        start += slice.len;
    }

    return lines;
}

/// Returns a copy of the entire buffer.
/// Caller owns memory.
pub fn getAllLines(buffer: *Buffer, allocator: std.mem.Allocator) ![]u8 {
    return buffer.getLines(allocator, 1, buffer.lineCount());
}

pub fn getIndex(buffer: *Buffer, row: u64, col: u64) u64 {
    assert(row <= buffer.lineCount());
    assert(row > 0);
    assert(col > 0);
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
    utils.assert(row <= buffer.lineCount() + 1, "row cannot be greater than the total rows in the buffer");
    utils.assert(row > 0, "row must be greater than 0");

    // in the findNodeWithLine() call we subtract 2 from row because
    // rows in the buffer are 1-based but in buffer.lines they're 0-based so
    // we subtract 1 and because we use 0 as the index for row 1 because that's
    // the first byte of the first row we need to subtract another 1.
    return if (row == 1)
        0
    else
        buffer.lines.tree.findNodeWithLine(&buffer.lines, row - 2).newline_index + 1;
}

pub fn indexOfLastByteAtRow(buffer: *Buffer, row: u64) u64 {
    utils.assert(row <= buffer.lineCount(), "row cannot be greater than the total rows in the buffer");
    return buffer.lines.tree.findNodeWithLine(&buffer.lines, row -| 1).newline_index;
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
    var index = min(index_, buffer.size());

    var row: u64 = 0;
    var newline_index: u64 = 0;
    while (row < buffer.lineCount()) : (row += 1) {
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

pub const LineIterator = struct {
    const Self = @This();

    buffer: *Buffer,
    start: u64,
    end: u64,
    current_line: u64,

    pub fn init(buffer: *Buffer, first_line: u64, last_line: u64) LineIterator {
        utils.assert(first_line <= last_line, "first_line must be <= last_line");
        utils.assert(last_line <= buffer.lineCount(), "last_line cannot be greater than the total rows in the buffer");

        const start = buffer.indexOfFirstByteAtRow(first_line);
        const end = buffer.indexOfLastByteAtRow(last_line) + 1;
        // std.debug.print("end{} {}\n", .{ end, last_line });
        return .{
            .buffer = buffer,
            .start = start,
            .end = end,
            .current_line = first_line,
        };
    }

    pub fn next(self: *Self) ?[]const u8 {
        if (self.start >= self.end) {
            return null;
        }
        const current_line_end = self.buffer.indexOfLastByteAtRow(self.current_line) + 1;

        const piece_info = self.buffer.lines.tree.findNode(self.start);
        const slice = piece_info.piece.content(&self.buffer.lines)[piece_info.relative_index..];

        const end = if (self.start + slice.len < current_line_end)
            slice.len
        else
            current_line_end -| self.start;

        const relevant_content = slice[0..end];
        self.start += relevant_content.len;
        if (self.start >= current_line_end) self.current_line += 1;

        return relevant_content;
    }
};

/// BufferIterator is end exclusive
pub const BufferIterator = struct {
    const Self = @This();

    pt: *PieceTable,
    start: u64,
    end: u64,

    pub fn init(buffer: *Buffer, start: u64, end: u64) BufferIterator {
        return .{
            .pt = &buffer.lines,
            .start = start,
            .end = end,
        };
    }

    pub fn initLines(buffer: *Buffer, first_line: u64, last_line: u64) BufferIterator {
        utils.assert(first_line <= last_line, "first_line must be <= last_line");
        utils.assert(last_line <= buffer.lineCount(), "last_line cannot be greater than the total rows in the buffer");

        const start = buffer.indexOfFirstByteAtRow(first_line);
        const end = buffer.indexOfLastByteAtRow(last_line) + 1;
        return .{
            .pt = &buffer.lines,
            .start = start,
            .end = end,
        };
    }

    pub fn next(self: *Self) ?[]const u8 {
        if (self.start >= self.end) return null;
        const piece_info = self.pt.tree.findNode(self.start);
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

pub const ReverseBufferIterator = struct {
    const Self = @This();

    pt: *PieceTable,
    start: u64,
    end: u64,
    done: bool = false,

    pub fn init(buffer: *Buffer, start: u64, end: u64) ReverseBufferIterator {
        return .{
            .pt = &buffer.lines,
            .start = start,
            .end = std.math.min(buffer.size() - 1, end),
        };
    }

    pub fn initLines(buffer: *Buffer, first_line: u64, last_line: u64) ReverseBufferIterator {
        utils.assert(first_line <= last_line, "first_line must be <= last_line");
        utils.assert(last_line <= buffer.lineCount(), "last_line cannot be greater than the total rows in the buffer");

        const start = buffer.indexOfFirstByteAtRow(first_line);
        const end = buffer.indexOfLastByteAtRow(last_line);
        return .{
            .pt = &buffer.lines,
            .start = start,
            .end = std.math.min(buffer.size() - 1, end),
        };
    }

    pub fn next(self: *Self) ?[]const u8 {
        if (self.done) return null;
        if (self.end <= self.start or self.end == 0) self.done = true;

        const piece_info = self.pt.tree.findNode(self.end);
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

            self.end -|= string.len;
            return string;
        }
    }
};

pub fn size(buffer: *Buffer) u64 {
    return buffer.lines.tree.size;
}

pub fn lineCount(buffer: *Buffer) u64 {
    return buffer.lines.tree.newlines_count;
}

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

    buffer.cursor_index = min(i, buffer.size() - 1);
}

pub fn moveRelativeRow(buffer: *Buffer, row_offset: i64) void {
    if (buffer.size() == 0) return;
    if (row_offset == 0) return;

    const cursor = buffer.getRowAndCol(buffer.cursor_index);

    var new_row = @intCast(i64, cursor.row) + row_offset;
    if (row_offset < 0) new_row = max(1, new_row) else new_row = min(new_row, buffer.lineCount());

    buffer.cursor_index = buffer.indexOfFirstByteAtRow(@intCast(u64, new_row));

    const old_col = cursor.col;
    moveRelativeColumn(buffer, @intCast(i64, old_col - 1), true);
}

pub fn moveAbsolute(buffer: *Buffer, row: u64, col: u64) void {
    if (row > buffer.lineCount()) return;
    buffer.cursor_index = buffer.getIndex(row, col);
}

////////////////////////////////////////////////////////////////////////////////
// Selection
////////////////////////////////////////////////////////////////////////////////

pub fn setSelection(buffer: *Buffer, const_start: u64, const_end: u64) void {
    const end = std.math.min(const_end, buffer.size());
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

////////////////////////////////////////////////////////////////////////////////
// History
////////////////////////////////////////////////////////////////////////////////

pub fn pushHistory(buffer: *Buffer, move_to_new_node: bool) !void {
    var new_node = try buffer.allocator.create(HistoryTree.Node);
    errdefer buffer.allocator.destroy(new_node);
    const slice = try buffer.lines.tree.treeToPieceInfoArray(buffer.allocator);
    new_node.* = .{ .data = .{
        .cursor_index = buffer.cursor_index,
        .pieces = slice,
    } };

    if (buffer.history.root == null)
        buffer.history.root = new_node;

    if (buffer.history_node) |node|
        node.appendChild(new_node);

    if (move_to_new_node)
        buffer.history_node = new_node;

    buffer.metadata.history_dirty = false;
}

pub fn undo(buffer: *Buffer) !void {
    if (buffer.history_node == null) return;

    if (buffer.metadata.history_dirty)
        try buffer.pushHistory(true);

    var node = buffer.history_node.?.parent orelse return;

    var tree_slice = node.data.pieces;
    var new_tree = try PieceTable.SplayTree.treeFromSlice(buffer.allocator, tree_slice);
    buffer.lines.tree.deinitAndSetAsNewTree(buffer.allocator, new_tree);

    buffer.history_node = node;
    buffer.cursor_index = node.data.cursor_index;
    buffer.cursor_index = std.math.min(buffer.cursor_index, buffer.size() - 1);
}

pub fn redo(buffer: *Buffer, index: u64) !void {
    if (buffer.history_node == null) return;
    var node = buffer.history_node.?.getChild(index) orelse return;

    var tree_slice = node.data.pieces;
    var new_tree = try PieceTable.SplayTree.treeFromSlice(buffer.allocator, tree_slice);
    buffer.lines.tree.deinitAndSetAsNewTree(buffer.allocator, new_tree);

    buffer.history_node = node;
    buffer.cursor_index = node.data.cursor_index;
}
