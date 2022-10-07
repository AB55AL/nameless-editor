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
const PieceTable = @import("piece_table.zig");
const utf8 = @import("utf8.zig");
const globals = @import("../globals.zig");

const utils = @import("utils.zig");

const global = globals.global;
const internal = globals.internal;

const Buffer = @This();

pub const MetaData = struct {
    file_path: []u8,
    file_last_mod_time: i128,
    dirty: bool,
};

metadata: MetaData,
index: ?u32,
cursor: Cursor,
/// The data structure holding every line in the buffer
lines: PieceTable,

pub fn init(allocator: std.mem.Allocator, file_path: []const u8, buf: []const u8) !Buffer {
    const static = struct {
        var index: u32 = 0;
    };
    defer static.index += 1;
    var fp = try allocator.alloc(u8, file_path.len);
    std.mem.copy(u8, fp, file_path);

    var metadata = MetaData{
        .file_path = fp,
        .file_last_mod_time = 0,
        .dirty = false,
    };

    var buffer = Buffer{
        .index = static.index,
        .metadata = metadata,
        .cursor = .{ .row = 1, .col = 1, .index = 0 },
        .lines = try PieceTable.init(allocator, buf),
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
    buffer.deinitNoTrash(internal.allocator);

    var index_in_global_array: usize = 0;
    for (global.buffers.items) |b, i| {
        if (b.index.? == buffer.index.?) {
            index_in_global_array = i;
            break;
        }
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

    allocator.free(buffer.metadata.file_path);
}

/// Deinits the members of the buffer and destroys the buffer.
/// Pointers to this buffer are all invalidated
pub fn deinitAndDestroy(buffer: *Buffer, allocator: std.mem.Allocator) void {
    buffer.deinitNoTrash(internal.allocator);
    allocator.destroy(buffer);
}

pub fn insertBeforeCursor(buffer: *Buffer, string: []const u8) !void {
    try buffer.lines.insert(buffer.cursor.index, string);
    buffer.metadata.dirty = true;
}

pub fn deleteBeforeCursor(buffer: *Buffer, characters_to_delete: u64) !void {
    const old_index = buffer.cursor.index;
    Cursor.moveRelative(buffer, 0, -@intCast(i64, characters_to_delete));
    const new_index = buffer.cursor.index;

    const bytes_to_delete = old_index - new_index;
    try buffer.lines.delete(buffer.cursor.index, bytes_to_delete);
    buffer.metadata.dirty = true;
}

pub fn deleteAfterCursor(buffer: *Buffer, characters_to_delete: u64) !void {
    Cursor.moveRelative(buffer, 0, @intCast(i64, characters_to_delete));
    try buffer.deleteBeforeCursor(characters_to_delete);
}

// TODO: Implement this
// pub fn deleteRows(buffer: *Buffer, start_row: u32, end_row: u32) !void {
//     assert(start_row <= end_row);
//     assert(end_row <= buffer.lines.count);
// }

// TODO: Implement this
// pub fn deleteRange(buffer: *Buffer, start_row: u32, start_col: u32, end_row: u32, end_col: u32) !void {
//     if (start_row > end_row)
//         return error.InvalidRange;
//     _ = end_col;
//     _ = start_col;

//     buffer.metadata.dirty = true;
// }

// TODO: Implement this
// pub fn replaceAllWith(buffer: *Buffer, string: []const u8) !void {
//     _ = string;
//     buffer.metadata.dirty = true;
// }

// TODO: this
// pub fn replaceRange(buffer: *Buffer, string: []const u8, start_row: i32, start_col: i32, end_row: i32, end_col: i32) !void {
// }

// TODO: Use fragmentOfLine() for the slice
pub fn countCodePointsAtRow(buffer: *Buffer, row: u64) usize {
    assert(row <= buffer.lines.newlines_count);
    const slice = buffer.getLine(row) catch unreachable;
    defer internal.allocator.free(slice);
    return unicode.utf8CountCodepoints(slice) catch unreachable;
}

// TODO: implement
// pub fn insureLastByteIsNewline(buffer: *Buffer) !void {
// }

pub fn clear(buffer: *Buffer) !void {
    _ = buffer;
}

pub fn getLine(buffer: *Buffer, row: u64) ![]u8 {
    assert(row <= buffer.lines.newlines_count);
    return buffer.lines.getLine(row - 1);
}

pub fn getLines(buffer: *Buffer, first_line: u32, last_line: u32) ![]u8 {
    assert(last_line >= first_line);
    assert(first_line > 0);
    assert(last_line <= buffer.lines.newlines_count);
    return buffer.lines.getLines(first_line - 1, last_line - 1);
}

/// Returns a copy of the entire buffer.
/// Caller owns memory.
pub fn getAllLines(buffer: *Buffer) ![]u8 {
    var array = try internal.allocator.alloc(u8, buffer.lines.size);
    return buffer.lines.buildIntoArray(array);
}

pub fn getIndex(buffer: *Buffer, row: u64, col: u64) u64 {
    assert(row <= buffer.lines.newlines_count);
    var index: u64 = if (row == 1) 0 else buffer.lines.findNodeWithLine(row - 2).newline_index + 1;

    var char_count: usize = 0;
    var i: usize = 0;
    while (char_count < col) {
        const byte = buffer.lines.byteAt(i + index);
        const byte_seq_len = unicode.utf8ByteSequenceLength(byte) catch 0;
        if (byte == '\n') {
            break;
        } else if (byte_seq_len > 0) {
            char_count += 1;
            i += byte_seq_len;
        } else { // Continuation byte
            i += 1;
        }
    }

    return index + i - 1;
}
