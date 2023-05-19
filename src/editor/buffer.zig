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
const core = @import("../core.zig");
const globals = core.globals;
const BufferHandle = core.BufferHandle;
const utf8 = @import("../utf8.zig");
const NaryTree = @import("../nary.zig").NaryTree;
const utils = @import("../utils.zig");
const file_io = @import("file_io.zig");

const HistoryTree = NaryTree(HistoryInfo);

const Buffer = @This();

pub const Change = struct {
    start_index: u64,
    start_point: Point,
    delete_len: u64,
    inserted_len: u64,
};

pub const Size = struct {
    size: u64,
    line_count: u64,
};

pub const Range = struct {
    start: u64,
    end: u64,

    pub fn overlaps(a: Range, b: Range) bool {
        return a.start <= b.end and a.end >= b.start;
    }

    /// Returns an index that is an offset of Range.end. The index would be the first
    /// byte of a utf8 sequence
    pub fn endPreviousCP(range: Range, buffer: *Buffer) u64 {
        var end = range.end -| 1;
        while (utf8.byteType(buffer.lines.byteAt(end)) == .continue_byte and end > 0)
            end -= 1;

        return end;
    }
};

pub const PointRange = struct {
    start: Point,
    end: Point,
};

pub const Index = u64;

pub const Point = struct {
    row: u64 = 1,
    col: u64 = 1,

    pub fn min(a: Point, b: Point) Point {
        if (a.row == b.row) {
            if (a.col <= b.col) return a else return b;
        }
        if (a.row < b.row) return a else return b;
    }

    pub fn max(a: Point, b: Point) Point {
        if (a.row == b.row) {
            if (a.col >= b.col) return a else return b;
        }
        if (a.row > b.row) return a else return b;
    }

    pub fn addRow(point: Point, offset: u64) Point {
        return .{ .row = point.row + offset, .col = point.col };
    }

    pub fn addCol(point: Point, offset: u64) Point {
        return .{ .row = point.row, .col = point.col + offset };
    }

    pub fn subRow(point: Point, offset: u64) Point {
        return .{ .row = std.math.max(1, point.row - offset), .col = point.col };
    }

    pub fn subCol(point: Point, offset: u64) Point {
        return .{ .row = point.row, .col = std.math.max(1, point.col - offset) };
    }

    pub fn setRow(point: Point, row: u64) Point {
        return .{ .row = std.math.max(1, row), .col = point.col };
    }

    pub fn setCol(point: Point, col: u64) Point {
        return .{ .row = point.row, .col = std.math.max(1, col) };
    }
};

pub const MetaData = struct {
    file_path: []u8,
    buffer_type: []u8,
    file_last_mod_time: i128,
    dirty: bool = false,
    history_dirty: bool = false,
    read_only: bool = false,

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
    anchor: Point = .{ .row = 0, .col = 0 }, // 0,0 means no selection
    kind: Kind = .regular,

    pub fn get(selection: Selection, cursor: Point) PointRange {
        var start = selection.anchor.min(cursor);
        var end = selection.anchor.max(cursor);
        start.col = max(start.col, 1);
        end.col = max(end.col, 1);

        if (selection.kind == .block and end.col < start.col) {
            const temp = start.col;
            start.col = end.col;
            end.col = temp;
        }

        end.col +|= 1; // end exclusive

        return switch (selection.kind) {
            .regular, .block => .{ .start = start, .end = end },
            .line => .{ .start = .{ .row = start.row, .col = 1 }, .end = .{ .row = end.row + 1, .col = 1 } },
        };
    }

    pub fn selected(selection: Selection) bool {
        return !std.meta.eql(selection.anchor, .{ .row = 0, .col = 0 });
    }

    pub fn reset(selection: *Selection) void {
        selection.anchor = .{ .row = 0, .col = 0 };
    }
};

metadata: MetaData,
/// The data structure holding every line in the buffer
lines: PieceTable,
allocator: std.mem.Allocator,

history: HistoryTree = HistoryTree{},
history_node: ?*HistoryTree.Node = null,
selection: Selection = .{},
/// Indices values stored here will be updated on every change of the buffer
marks: std.AutoArrayHashMapUnmanaged(u32, Index) = .{},
bhandle: ?BufferHandle,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8, buf: []const u8, bhandle: ?BufferHandle) !Buffer {
    var fp = try allocator.dupe(u8, file_path);

    const index = std.mem.lastIndexOf(u8, fp, ".");
    const buffer_type = if (index) |i| fp[i + 1 ..] else "";
    var bt = try allocator.dupe(u8, buffer_type);

    var metadata = MetaData{
        .file_path = fp,
        .buffer_type = bt,
        .file_last_mod_time = 0,
        .dirty = false,
        .history_dirty = false,
    };

    var buffer = Buffer{
        .metadata = metadata,
        .lines = try PieceTable.init(allocator, buf),
        .allocator = allocator,
        .bhandle = bhandle,
    };

    try buffer.insureLastByteIsNewline();
    try buffer.pushHistory(0, true);

    return buffer;
}

/// Deinits the members of the buffer but does not destroy the buffer.
pub fn deinitNoDestroy(buffer: *Buffer) void {
    buffer.lines.deinit(buffer.allocator);
    buffer.marks.deinit(buffer.allocator);
    buffer.allocator.free(buffer.metadata.file_path);
    buffer.allocator.free(buffer.metadata.buffer_type);

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

// TODO: CHECK THE INDEX TYPE
pub fn insertAt(buffer: *Buffer, index: u64, string: []const u8) !void {
    if (buffer.metadata.read_only) return error.ModifyingReadOnlyBuffer;

    try buffer.validateInsertionPoint(index);
    try buffer.lines.insert(buffer.allocator, index, string);
    buffer.metadata.setDirty();
    try buffer.insureLastByteIsNewline();

    var iter = buffer.marks.iterator();
    while (iter.next()) |kv| kv.value_ptr.* = updateIndexInsert(kv.value_ptr.*, index, string.len);

    if (!builtin.is_test) {
        const change = Change{ .start_index = index, .start_point = .{}, .delete_len = 0, .inserted_len = string.len };
        core.gs().hooks.dispatch("after_insert", .{ buffer, buffer.bhandle, change });
    }
}

/// End exclusive
pub fn deleteRange(buffer: *Buffer, start: u64, end: u64) !void {
    if (buffer.metadata.read_only) return error.ModifyingReadOnlyBuffer;

    const s = min(start, end);
    const e = max(start, end);
    const deletion_len = e - s;

    try buffer.validateRange(s, e);
    try buffer.lines.delete(buffer.allocator, s, e -| 1);

    buffer.metadata.setDirty();
    try buffer.insureLastByteIsNewline();

    var iter = buffer.marks.iterator();
    while (iter.next()) |kv| kv.value_ptr.* = updateIndexDelete(kv.value_ptr.*, start, deletion_len);

    if (!builtin.is_test) {
        const change = Change{ .start_index = start, .start_point = .{}, .delete_len = deletion_len, .inserted_len = 0 };
        core.gs().hooks.dispatch("after_delete", .{ buffer, buffer.bhandle, change });
    }
}

pub fn replaceAllWith(buffer: *Buffer, string: []const u8) !void {
    if (buffer.metadata.read_only) return error.ModifyingReadOnlyBuffer;

    var root = PieceTable.PieceNode.deinitTree(buffer.lines.tree.root, buffer.allocator);
    if (root) |r| buffer.allocator.destroy(r);
    buffer.lines.tree = .{};

    try buffer.lines.insert(buffer.allocator, 0, string);
    try buffer.insureLastByteIsNewline();
    buffer.metadata.setDirty();

    var iter = buffer.marks.iterator();
    while (iter.next()) |kv| kv.value_ptr.* = 0;
}

pub fn clear(buffer: *Buffer) !void {
    if (buffer.metadata.read_only) return error.ModifyingReadOnlyBuffer;

    var root = PieceTable.PieceNode.deinitTree(buffer.lines.tree.root, buffer.allocator);
    if (root) |r| buffer.allocator.destroy(r);

    buffer.lines.tree = .{};
    try buffer.insureLastByteIsNewline();
    buffer.metadata.setDirty();

    var iter = buffer.marks.iterator();
    while (iter.next()) |kv| kv.value_ptr.* = 0;
}

////////////////////////////////////////////////////////////////////////////////
// Convenience insertion and deletion functions
////////////////////////////////////////////////////////////////////////////////
pub fn insertAtPoint(buffer: *Buffer, rc: Point, string: []const u8) !void {
    const index = buffer.getIndex(rc);
    try buffer.insertAt(index, string);
}

pub fn deleteBefore(buffer: *Buffer, index: Index) !void {
    if (index == 0) return;

    var i = index - 1;
    var byte = buffer.lines.byteAt(i);
    while (utf8.byteType(byte) == .continue_byte) {
        i -= 1;
        byte = buffer.lines.byteAt(i);
    }

    try buffer.deleteRange(i, index);
}

pub fn deleteAfterCursor(buffer: *Buffer, index: Index) !void {
    var byte = buffer.lines.byteAt(index);
    var len = try unicode.utf8ByteSequenceLength(byte);
    try buffer.deleteRange(index, index + len);
}

pub fn deleteRows(buffer: *Buffer, start_row: u64, end_row: u64) !void {
    assert(start_row <= end_row);
    assert(end_row <= buffer.lineCount());

    const start_index = buffer.indexOfFirstByteAtRow(start_row);
    const end_index = buffer.indexOfLastByteAtRow(end_row) + 1;

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

pub fn validateInsertionPoint(buffer: *Buffer, index: Index) !void {
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

pub fn countCodePointsAtRow(buffer: *Buffer, arg_row: u64) u64 {
    const row = std.math.min(arg_row, buffer.lineCount());
    var count: u64 = 0;
    var iter = LineIterator.initLines(buffer, row, row);
    while (iter.next()) |slice|
        count += utf8.countCodepoints(slice);

    return count;
}

pub fn insureLastByteIsNewline(buffer: *Buffer) !void {
    if (buffer.size() == 0 or buffer.lines.byteAt(buffer.size() - 1) != '\n') {
        try buffer.lines.insert(buffer.allocator, buffer.size(), "\n");
    }
}

pub fn lineSize(buffer: *Buffer, line: u64) u64 {
    return buffer.indexOfLastByteAtRow(line) - buffer.indexOfFirstByteAtRow(line) + 1;
}

pub fn lineRangeSize(buffer: *Buffer, start_line: u64, end_line: u64) u64 {
    return buffer.indexOfLastByteAtRow(end_line) - buffer.indexOfFirstByteAtRow(start_line) + 1;
}

pub fn maxLineRangeSize(buffer: *Buffer, start_row: u64, end_row: u64) u64 {
    var s: u64 = 0;
    for (start_row..end_row + 1) |row| s = max(s, buffer.lineSize(row));
    return s;
}

pub fn codePointAt(buffer: *Buffer, index: u64) !u21 {
    return unicode.utf8Decode(buffer.codePointSliceAt(index));
}

pub fn codePointSliceAt(buffer: *Buffer, const_index: u64) []const u8 {
    var index = const_index;
    var byte = buffer.lines.byteAt(index);

    while (utf8.byteType(byte) != .start_byte) {
        // if we're here then the buffer contains invalid utf8 or the index is in
        // an invalid position, either way just move forward until we find a valid position
        index += 1;
        byte = buffer.lines.byteAt(index);
    }

    const count = unicode.utf8ByteSequenceLength(byte) catch 1;
    var piece_info = buffer.lines.tree.findNode(index);
    var i = piece_info.relative_index;
    const slice = piece_info.piece.content(&buffer.lines)[i .. i + count];

    return slice;
}

/// Searches the buffer for *string* and returns a slice of indices of all occurrences
/// within the given range
pub fn search(buffer: *Buffer, allocator: std.mem.Allocator, string: []const u8, start_row: u64, end_row: u64) !?[]u64 {
    if (string.len == 0) return null;

    const max_line_size = buffer.maxLineRangeSize(start_row, end_row);
    var line_buf = try buffer.allocator.alloc(u8, max_line_size);
    defer buffer.allocator.free(line_buf);

    var indices = std.ArrayListUnmanaged(u64){};
    errdefer indices.deinit(allocator);

    for (start_row..end_row + 1) |row| {
        const full_line = buffer.getLineBuf(line_buf, row);
        var slicer: u64 = 0;
        while (slicer < full_line.len) { // get all matches of string in the same line
            var line = full_line[slicer..];
            if (line.len < string.len) break;

            var index = std.mem.indexOf(u8, line, string);
            if (index) |i| {
                try indices.append(allocator, slicer + i + buffer.indexOfFirstByteAtRow(row));
                slicer += string.len + i;
            } else break;
        }
    }

    return if (indices.items.len == 0) null else indices.items;
}

pub fn getLinesBuf(buffer: *Buffer, buf: []u8, first_line: u64, last_line: u64) []u8 {
    utils.assert(last_line >= first_line, "");
    utils.assert(first_line > 0, "");
    utils.assert(last_line <= buffer.lineCount(), "");
    utils.assert(buf.len >= buffer.lineRangeSize(first_line, last_line), "");

    const start = buffer.indexOfFirstByteAtRow(first_line);
    const end = buffer.indexOfLastByteAtRow(last_line) + 1;
    var iter = BufferIterator.init(buffer, start, end);
    var i: u64 = 0;
    while (iter.next()) |slice| {
        std.mem.copy(u8, buf[i..], slice);
        i += slice.len;
    }

    return buf[0..i];
}

pub fn getLineBuf(buffer: *Buffer, buf: []u8, row: u64) []u8 {
    return buffer.getLinesBuf(buf, row, row);
}

pub fn getLine(buffer: *Buffer, allocator: std.mem.Allocator, row: u64) ![]u8 {
    var line = try allocator.alloc(u8, buffer.lineSize(row));
    return buffer.getLineBuf(line, row);
}

pub fn getLines(buffer: *Buffer, allocator: std.mem.Allocator, first_line: u64, last_line: u64) ![]u8 {
    var lines = try allocator.alloc(u8, buffer.lineRangeSize(first_line, last_line));
    return buffer.getLinesBuf(lines, first_line, last_line);
}

/// Returns a copy of the entire buffer.
/// Caller owns memory.
pub fn getAllLines(buffer: *Buffer, allocator: std.mem.Allocator) ![]u8 {
    var lines = try allocator.alloc(u8, buffer.size());
    return buffer.getLinesBuf(lines, 1, buffer.lineCount());
}

pub fn getIndex(buffer: *Buffer, rc: Point) u64 {
    const row = std.math.min(buffer.lineCount(), rc.row);
    const col = rc.col;
    assert(row <= buffer.lineCount());
    assert(row > 0);
    assert(col > 0);
    var index: u64 = buffer.indexOfFirstByteAtRow(row);

    var i: u64 = 0;
    var char_count: u64 = 0;

    var iter = BufferIterator.initLines(buffer, row, row);
    outer: while (iter.next()) |string| {
        var j: u64 = 0;
        while (j < string.len) {
            var byte = string[j];
            var len = unicode.utf8ByteSequenceLength(byte) catch 1;
            char_count += 1;

            if (char_count == rc.col) break :outer;

            j += len;
            i += len;
        }
    }

    return index + i;
}

pub fn indexOfFirstByteAtRow(buffer: *Buffer, arg_row: u64) u64 {
    const row = utils.bound(arg_row, 1, buffer.lineCount());

    // in the findNodeWithLine() call we subtract 2 from row because
    // rows in the buffer are 1-based but in buffer.lines they're 0-based so
    // we subtract 1 and because we use 0 as the index for row 1 because that's
    // the first byte of the first row we need to subtract another 1.
    return if (row == 1)
        0
    else
        buffer.lines.tree.findNodeWithLine(&buffer.lines, row - 2).newline_index + 1;
}

pub fn rowOfIndex(buffer: *Buffer, index: u64) struct { row: u64, index: u64 } {
    if (index >= buffer.size()) return .{
        .row = buffer.lineCount(),
        .index = buffer.indexOfFirstByteAtRow(buffer.lineCount()),
    };

    var lower_bound: u64 = 1;
    var upper_bound: u64 = buffer.lineCount();
    var row = (upper_bound + lower_bound) / 2;

    var start: u64 = 0;
    var end: u64 = 0;
    while (true) {
        start = buffer.indexOfFirstByteAtRow(row);
        end = buffer.indexOfLastByteAtRow(row);

        if ((index >= start and index <= end) or upper_bound == lower_bound)
            break;

        if (index < start)
            upper_bound = row - 1
        else
            lower_bound = row + 1;

        row = (upper_bound + lower_bound) / 2;
    }

    return .{ .row = row, .index = start };
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

pub fn getPoint(buffer: *Buffer, index_: u64) Point {
    const index = min(index_, buffer.size());
    const roi = buffer.rowOfIndex(index);

    var col: u64 = 1;
    var i: u64 = roi.index;
    while (i < index) {
        const byte = buffer.lines.byteAt(i);
        const len = unicode.utf8ByteSequenceLength(byte) catch 1;
        col += 1;
        i += len;
    }

    return .{ .row = roi.row, .col = col };
}

pub fn getColIndex(buffer: *Buffer, point: Point) u64 {
    const index = buffer.getIndex(point);
    const line_start = buffer.indexOfFirstByteAtRow(point.row);
    return index - line_start;
}

/// Offsets the index to be relative to the line it is in
pub fn offsetIndexToLine(buffer: *Buffer, index: u64) u64 {
    const roi = buffer.rowOfIndex(index);
    return index - roi.index;
}

pub fn pointRangeToRange(buffer: *Buffer, range: PointRange) Range {
    const start = range.start.min(range.end);
    const end = range.start.max(range.end);

    const start_index = buffer.getIndex(start);
    const end_index = buffer.getIndex(end);

    return .{ .start = start_index, .end = end_index };
}

pub const AllocLineIterator = struct {
    const Self = @This();

    inner_iter: LineIterator,
    buf: []u8,
    current_line: u64,

    pub fn initPoint(buffer: *Buffer, start: Point, end: Point) !AllocLineIterator {
        var buf = try buffer.allocator.alloc(u8, buffer.maxLineRangeSize(start.row, end.row));
        return .{
            .inner_iter = LineIterator.initPoint(buffer, .{ .start = start, .end = end }),
            .buf = buf,
            .current_line = start.row -| 1,
        };
    }

    pub fn initLines(buffer: *Buffer, start_row: u64, end_row: u64) !AllocLineIterator {
        var buf = try buffer.allocator.alloc(u8, buffer.maxLineRangeSize(start_row, end_row));
        return .{
            .inner_iter = LineIterator.initLines(buffer, start_row, end_row),
            .buf = buf,
            .current_line = start_row -| 1,
        };
    }

    pub fn deinit(self: *AllocLineIterator) void {
        self.inner_iter.buffer.allocator.free(self.buf);
    }

    pub fn next(self: *AllocLineIterator) ?[]u8 {
        self.current_line += 1;
        var i: u64 = 0;
        while (self.inner_iter.next()) |string| {
            std.mem.copy(u8, self.buf[i..], string);
            i += string.len;

            if (string[string.len - 1] == '\n') break;
        }

        if (i > 0) return self.buf[0..i];

        return null;
    }
};

pub const LineIterator = struct {
    const Self = @This();

    buffer: *Buffer,
    start: u64,
    end: u64,
    current_line: u64,

    pub fn initPoint(buffer: *Buffer, range: PointRange) LineIterator {
        const r = buffer.pointRangeToRange(range);

        return .{
            .buffer = buffer,
            .start = r.start,
            .end = r.end,
            .current_line = range.start.min(range.end).row,
        };
    }

    pub fn initLines(buffer: *Buffer, first_line: u64, last_line: u64) LineIterator {
        utils.assert(first_line <= last_line, "first_line must be <= last_line");
        utils.assert(last_line <= buffer.lineCount(), "last_line cannot be greater than the total rows in the buffer");

        const start = buffer.indexOfFirstByteAtRow(first_line);
        const end = buffer.indexOfLastByteAtRow(last_line) + 1;
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
        const current_line_end = std.math.min(self.buffer.indexOfLastByteAtRow(self.current_line) + 1, self.end);

        const piece_info = self.buffer.lines.tree.findNode(self.start);
        const slice = piece_info.piece.content(&self.buffer.lines)[piece_info.relative_index..];

        const end = min(slice.len, current_line_end -| self.start);

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

        const end = min(string.len, self.end - self.start);
        return string[0..end];
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

// TODO: Faster move code
pub fn moveRelativeColumn(buffer: *Buffer, index: Index, col_offset: i64) Index {
    if (col_offset == 0) return index;

    const abs_offset = std.math.absCast(col_offset);
    const point = buffer.getPoint(index);

    const col = blk: {
        if (col_offset > 0) {
            const row_size = buffer.countCodePointsAtRow(point.row);
            break :blk min(row_size, point.col +| abs_offset);
        } else {
            break :blk max(1, point.col -| abs_offset);
        }
    };

    return buffer.getIndex(point.setCol(col));
}

// TODO: Faster move code
pub fn moveRelativeRow(buffer: *Buffer, index: Index, row_offset: i64) Index {
    if (row_offset == 0) return index;

    const point = buffer.getPoint(index);
    const roi = buffer.rowOfIndex(index);
    const abs_offset = std.math.absCast(row_offset);
    var row = if (row_offset > 0) roi.row +| abs_offset else roi.row -| abs_offset;
    row = utils.bound(row, 1, buffer.lineCount());

    return buffer.getIndex(.{ .row = row, .col = point.col });
}

////////////////////////////////////////////////////////////////////////////////
// History
////////////////////////////////////////////////////////////////////////////////

pub fn pushHistory(buffer: *Buffer, cursor_index: Index, move_to_new_node: bool) !void {
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

pub fn undo(buffer: *Buffer, cursor_index: Index) !u64 {
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

pub fn redo(buffer: *Buffer, index: Index) !?Index {
    if (buffer.history_node == null) return null;
    var node = buffer.history_node.?.getChild(index) orelse return null;

    var tree_slice = node.data.pieces;
    var new_tree = try PieceTable.SplayTree.treeFromSlice(buffer.allocator, tree_slice);
    buffer.lines.tree.deinitAndSetAsNewTree(buffer.allocator, new_tree);

    buffer.history_node = node;

    return node.data.cursor_index;
}

////////////////////////////////////////////////////////////////////////////////
// Markers
////////////////////////////////////////////////////////////////////////////////
pub fn putMarker(buffer: *Buffer, mark: Index) !u32 {
    while (true) {
        const key = std.crypto.random.int(u32);
        if (buffer.marks.getKey(key) == null) {
            try buffer.marks.put(buffer.allocator, key, mark);
            return key;
        }
    }
}

pub fn removeMarker(buffer: *Buffer, key: u32) void {
    _ = buffer.marks.swapRemove(key);
}

fn updateIndexInsert(to_update: Index, change_index: Index, insertion_len: u64) Index {
    if (change_index > to_update) return to_update; // no need to update
    return to_update +| insertion_len;
}

fn updateIndexDelete(to_update: Index, change_index: Index, deletion_len: u64) Index {
    if (change_index > to_update) return to_update; // no need to update
    return to_update -| deletion_len;
}

////////////////////////////////////////////////////////////////////////////////
// Metadata setters
////////////////////////////////////////////////////////////////////////////////
pub fn setBufferType(buffer: *Buffer, new_bt: []const u8) !void {
    var buffer_type = try buffer.allocator.alloc(u8, new_bt.len);
    std.mem.copy(u8, buffer_type, new_bt);
    buffer.allocator.free(buffer.metadata.buffer_type);
    buffer.metadata.buffer_type = buffer_type;
}

pub fn setFilePath(buffer: *Buffer, new_fp: []const u8) !void {
    var file_path = try buffer.allocator.alloc(u8, new_fp.len);
    std.mem.copy(u8, file_path, new_fp);
    buffer.allocator.free(buffer.metadata.file_path);
    buffer.metadata.file_path = file_path;
}
