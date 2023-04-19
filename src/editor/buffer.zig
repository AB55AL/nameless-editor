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

    /// Returns an index that is an offset of Range.end. The index would be the first
    /// byte of a utf8 sequence
    pub fn endPreviousCP(range: Range, buffer: *Buffer) u64 {
        var end = range.end -| 1;
        while (utf8.byteType(buffer.lines.byteAt(end)) == .continue_byte and end > 0)
            end -= 1;

        return end;
    }
};

pub const Position = struct {
    index: u64,
    row: u64,
    col: u64,

    pub fn rowCol(pos: Position) RowCol {
        return .{
            .row = pos.row,
            .col = pos.col,
        };
    }
};

pub const RowCol = struct {
    row: u64 = 1,
    col: u64 = 1,

    pub fn min(a: RowCol, b: RowCol) RowCol {
        if (a.row == b.row) {
            if (a.col <= b.col) return a else return b;
        }
        if (a.row < b.row) return a else return b;
    }

    pub fn max(a: RowCol, b: RowCol) RowCol {
        if (a.row == b.row) {
            if (a.col >= b.col) return a else return b;
        }
        if (a.row > b.row) return a else return b;
    }

    pub fn moveRelativeColumn(rc: RowCol, buffer: *Buffer, col_offset: i64, stop_before_newline: bool) Position {
        const index = buffer.getIndex(rc);
        return buffer.moveRelativeColumn(index, col_offset, stop_before_newline);
    }

    pub fn moveRelativeRow(rc: RowCol, buffer: *Buffer, row_offset: i64) Position {
        const index = buffer.getIndex(rc);
        return buffer.moveRelativeRow(index, row_offset);
    }
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

pub const Selection = struct {
    const Kind = enum { regular, block, line };
    start: RowCol = .{},
    end: RowCol = .{},
    kind: Kind = .regular,

    pub fn reset(selection: *Selection) void {
        selection.start = .{};
        selection.end = selection.start;
    }
};

metadata: MetaData,
index: u32,
/// The data structure holding every line in the buffer
lines: PieceTable,
allocator: std.mem.Allocator,

history: HistoryTree = HistoryTree{},
history_node: ?*HistoryTree.Node = null,
selection: Selection = .{},

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
        .lines = try PieceTable.init(allocator, buf),
        .allocator = allocator,
    };

    try buffer.insureLastByteIsNewline();
    try buffer.pushHistory(0, true);

    return buffer;
}

/// Deinits the members of the buffer but does not destroy the buffer.
pub fn deinitNoDestroy(buffer: *Buffer) void {
    buffer.lines.deinit(buffer.allocator);
    buffer.allocator.free(buffer.metadata.file_path);
    buffer.allocator.free(buffer.metadata.file_type);

    buffer.history.deinitTree(buffer.allocator, struct {
        fn f(allocator: std.mem.Allocator, node_data: *HistoryInfo) void {
            allocator.free(node_data.pieces);
        }
    }.f);
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

/// End exclusive
pub fn deleteRange(buffer: *Buffer, start: u64, end: u64) !void {
    const s = min(start, end);
    const e = max(start, end);

    try buffer.validateRange(s, e);
    try buffer.lines.delete(buffer.allocator, s, e -| 1);

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
}

////////////////////////////////////////////////////////////////////////////////
// Convenience insertion and deletion functions
////////////////////////////////////////////////////////////////////////////////
pub fn insertAtRC(buffer: *Buffer, rc: RowCol, string: []const u8) !void {
    const index = buffer.getIndex(rc);
    try buffer.insertAt(index, string);
}

pub fn deleteBefore(buffer: *Buffer, index: u64) !void {
    if (index == 0) return;

    var i = index - 1;
    var byte = buffer.lines.byteAt(i);
    while (utf8.byteType(byte) == .continue_byte) {
        i -= 1;
        byte = buffer.lines.byteAt(i);
    }

    try buffer.deleteRange(i, index);
}

pub fn deleteAfterCursor(buffer: *Buffer, index: u64) !void {
    var byte = buffer.lines.byteAt(index);
    var len = try unicode.utf8ByteSequenceLength(byte);
    try buffer.deleteRange(index, index + len);
}

pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
    assert(start_row <= end_row);
    assert(end_row <= buffer.lineCount());

    const start_index = buffer.getIndex(.{ .row = start_row, .col = 1 });
    const end_index = if (end_row >= buffer.lineCount())
        buffer.size() + 1
    else
        buffer.getIndex(.{ .row = end_row + 1, .col = 1 });

    try buffer.deleteRange(start_index, end_index);
}

pub fn deleteRangeRC(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
    if (start_row > end_row)
        return error.InvalidRange;

    const start_index = buffer.getIndex(.{ .row = start_row, .col = start_col });
    const end_index = if (end_row > buffer.lineCount())
        buffer.size() + 1
    else
        buffer.getIndex(.{ .row = end_row, .col = end_col + 1 });

    try buffer.deleteRange(start_index, end_index);
}

// TODO: this
// pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
// }

pub fn validateInsertionPoint(buffer: *Buffer, index: u64) !void {
    const i = std.math.min(index, buffer.size() -| 1);

    if (i == 0 or
        i == buffer.size() - 1 or
        utf8.byteType(buffer.lines.byteAt(i)) == .start_byte)
        return;

    return error.InvalidInsertionPoint;
}

pub fn validateRange(buffer: *Buffer, start: u64, end: u64) !void {
    const s = std.math.min(start, buffer.size() -| 1);
    const e = std.math.min(end, buffer.size() -| 1);

    if (e == buffer.size() - 1 or
        utf8.byteType(buffer.lines.byteAt(s)) == .start_byte or
        utf8.byteType(buffer.lines.byteAt(e)) == .start_byte)
        return;

    return error.InvalidRange;
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

pub fn codePointAt(buffer: *Buffer, index: u64) !u21 {
    return unicode.utf8Decode(try buffer.codePointSliceAt(index));
}

pub fn codePointSliceAt(buffer: *Buffer, const_index: u64) ![]const u8 {
    var index = const_index;
    var byte = buffer.lines.byteAt(index);

    while (utf8.byteType(byte) != .start_byte) {
        // if we're here then the buffer contains invalid utf8 or the index is in
        // an invalid position, either way just move forward until we find a valid position
        index += 1;
        byte = buffer.lines.byteAt(index);
    }

    const count = try unicode.utf8ByteSequenceLength(byte);
    var piece_info = buffer.lines.tree.findNode(index);
    var i = piece_info.relative_index;
    const slice = piece_info.piece.content(&buffer.lines)[i .. i + count];

    return slice;
}

pub fn getLineBuf(buffer: *Buffer, buf: []u8, row: u64) []u8 {
    utils.assert(row <= buffer.lineCount(), "");
    utils.assert(buf.len <= buffer.lineSize(row), "");

    var iter = LineIterator.init(buffer, row, row);
    var start: u64 = 0;
    while (iter.next()) |slice| {
        std.mem.copy(u8, buf[start..], slice);
        start += slice.len;
    }

    return buf;
}

pub fn getLinesBuf(buffer: *Buffer, buf: []u8, first_line: u64, last_line: u64) []u8 {
    utils.assert(last_line >= first_line, "");
    utils.assert(first_line > 0, "");
    utils.assert(last_line <= buffer.lineCount(), "");
    utils.assert(buf.len <= buffer.lineRangeSize(first_line, last_line), "");

    var iter = LineIterator.init(buffer, first_line, last_line);
    var start: u64 = 0;
    while (iter.next()) |slice| {
        std.mem.copy(u8, buf[start..], slice);
        start += slice.len;
    }

    return buf;
}

pub fn getLine(buffer: *Buffer, allocator: std.mem.Allocator, row: u64) ![]u8 {
    var line = try allocator.alloc(u8, buffer.lineSize(row));
    return getLineBuf(buffer, line, row);
}

pub fn getLines(buffer: *Buffer, allocator: std.mem.Allocator, first_line: u64, last_line: u64) ![]u8 {
    var lines = try allocator.alloc(u8, buffer.lineRangeSize(first_line, last_line));
    return getLinesBuf(buffer, lines, first_line, last_line);
}

/// Returns a copy of the entire buffer.
/// Caller owns memory.
pub fn getAllLines(buffer: *Buffer, allocator: std.mem.Allocator) ![]u8 {
    return buffer.getLines(allocator, 1, buffer.lineCount());
}

pub fn getIndex(buffer: *Buffer, rc: RowCol) u64 {
    const row = std.math.min(buffer.lineCount(), rc.row);
    const col = rc.col;
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
            if (i > 0) i += 1; // if the line has more than just one newline char increment
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

pub fn getRowAndCol(buffer: *Buffer, index_: u64) RowCol {
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

pub fn moveRelativeColumn(buffer: *Buffer, index: u64, col_offset: i64, stop_before_newline: bool) Position {
    if (col_offset == 0 or (index == 0 and col_offset <= 0)) {
        const rc = buffer.getRowAndCol(index);
        return .{ .index = index, .row = rc.row, .col = rc.col };
    }

    var i = index;
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

    const rc = buffer.getRowAndCol(i);
    return .{
        .index = i,
        .row = rc.row,
        .col = rc.col,
    };
}

pub fn moveRelativeRow(buffer: *Buffer, index: u64, row_offset: i64) Position {
    if (buffer.size() == 0 or row_offset == 0) {
        const rc = buffer.getRowAndCol(index);
        return .{ .index = index, .row = rc.row, .col = rc.col };
    }

    const cursor = buffer.getRowAndCol(index);

    var new_row = @intCast(i64, cursor.row) + row_offset;
    if (row_offset < 0) new_row = max(1, new_row) else new_row = min(new_row, buffer.lineCount());

    const i = buffer.indexOfFirstByteAtRow(@intCast(u64, new_row));

    const old_col = cursor.col;
    return moveRelativeColumn(buffer, i, @intCast(i64, old_col - 1), true);
}

pub fn moveAbsolute(buffer: *Buffer, row: u64, col: u64) Position {
    const r = std.math.min(buffer.lineCount(), row);
    return .{
        .index = buffer.getIndex(.{ .row = r, .col = col }),
        .row = r,
        .col = col,
    };
}

////////////////////////////////////////////////////////////////////////////////
// History
////////////////////////////////////////////////////////////////////////////////

pub fn pushHistory(buffer: *Buffer, cursor_index: u64, move_to_new_node: bool) !void {
    var new_node = try buffer.allocator.create(HistoryTree.Node);
    errdefer buffer.allocator.destroy(new_node);
    const slice = try buffer.lines.tree.treeToPieceInfoArray(buffer.allocator);
    new_node.* = .{ .data = .{
        .cursor_index = std.math.min(cursor_index, buffer.size() -| 1),
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

pub fn undo(buffer: *Buffer, cursor_index: u64) !u64 {
    if (buffer.history_node == null) return cursor_index;

    if (buffer.metadata.history_dirty)
        try buffer.pushHistory(cursor_index, true);

    var node = buffer.history_node.?.parent orelse return cursor_index;

    var tree_slice = node.data.pieces;
    var new_tree = try PieceTable.SplayTree.treeFromSlice(buffer.allocator, tree_slice);
    buffer.lines.tree.deinitAndSetAsNewTree(buffer.allocator, new_tree);

    buffer.history_node = node;

    return node.data.cursor_index;
}

pub fn redo(buffer: *Buffer, index: u64) !?u64 {
    if (buffer.history_node == null) return null;
    var node = buffer.history_node.?.getChild(index) orelse return null;

    var tree_slice = node.data.pieces;
    var new_tree = try PieceTable.SplayTree.treeFromSlice(buffer.allocator, tree_slice);
    buffer.lines.tree.deinitAndSetAsNewTree(buffer.allocator, new_tree);

    buffer.history_node = node;

    return node.data.cursor_index;
}
