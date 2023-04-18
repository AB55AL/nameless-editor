const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const unicode = std.unicode;

const BufferWindow = @import("../ui/buffer.zig").BufferWindow;
const Buffer = @import("../editor/buffer.zig");
const BufferIterator = Buffer.BufferIterator;
const ReverseBufferIterator = Buffer.ReverseBufferIterator;
const Range = Buffer.Range;
const utils = @import("../utils.zig");
const utf8 = @import("../utf8.zig");

pub const white_space = blk: {
    var ws: [std.ascii.whitespace.len]u21 = undefined;
    for (std.ascii.whitespace, 0..) |c, i| ws[i] = c;
    break :blk ws;
};

pub fn findCodePointsInList(buffer: *Buffer, start: u64, list: []const u21) ?u64 {
    var offset = unicode.utf8ByteSequenceLength(buffer.lines.byteAt(start)) catch return null;
    var iter = BufferIterator.init(buffer, start + offset, buffer.size());
    var index = start + offset;
    while (iter.next()) |string| {
        var view = unicode.Utf8View.initUnchecked(string).iterator();
        while (view.nextCodepointSlice()) |slice| {
            defer index += slice.len;

            const cp = unicode.utf8Decode(slice) catch unreachable;
            if (utils.atLeastOneIsEqual(u21, list, cp))
                return index;
        }
    }

    return null;
}

pub fn findOutsideBlackList(buffer: *Buffer, start: u64, black_list: []const u21) ?u64 {
    var offset = unicode.utf8ByteSequenceLength(buffer.lines.byteAt(start)) catch return null;
    var iter = BufferIterator.init(buffer, start + offset, buffer.size());
    var index = start + offset;
    while (iter.next()) |string| {
        var view = unicode.Utf8View.initUnchecked(string).iterator();
        while (view.nextCodepointSlice()) |slice| {
            defer index += slice.len;

            const cp = unicode.utf8Decode(slice) catch unreachable;
            if (!utils.atLeastOneIsEqual(u21, black_list, cp)) {
                return index;
            }
        }
    }

    return null;
}

pub fn backFindCodePointsInList(buffer: *Buffer, start: u64, list: []const u21) ?u64 {
    if (start == 0) return null;
    var iter = ReverseBufferIterator.init(buffer, 0, start - 1);

    var index = start;
    while (iter.next()) |string| {
        var view = utf8.ReverseUtf8View(string);
        while (view.prevSlice()) |slice| {
            index -|= slice.len;

            const cp = unicode.utf8Decode(slice) catch unreachable;
            if (utils.atLeastOneIsEqual(u21, list, cp))
                return index;
        }
    }

    return null;
}

pub fn backFindOutsideBlackList(buffer: *Buffer, start: u64, list: []const u21) ?u64 {
    if (start == 0) return null;
    var iter = ReverseBufferIterator.init(buffer, 0, start - 1);

    var index = start;
    while (iter.next()) |string| {
        var view = utf8.ReverseUtf8View(string);
        while (view.prevSlice()) |slice| {
            index -|= slice.len;

            const cp = unicode.utf8Decode(slice) catch unreachable;
            if (!utils.atLeastOneIsEqual(u21, list, cp))
                return index;
        }
    }

    return null;
}

/// The way a motion works is as follows:
/// Find one of the delimiters and stop there and return.
/// If the starting point is one of the delimiters then move one character and return
/// White space is always ignored
pub fn forward(buffer: *Buffer, cursor_index: u64, delimiters: []const u21) ?Range {
    const start = cursor_index;

    {
        var cp = buffer.codePointAt(start) catch return null;
        if (utils.atLeastOneIsEqual(u21, delimiters, cp) and !utils.atLeastOneIsEqual(u21, &white_space, cp)) {
            var bytes = unicode.utf8CodepointSequenceLength(cp) catch return null;
            const end = start + bytes + 1;
            return .{ .start = start, .end = end };
        }
    }

    const mid = findCodePointsInList(buffer, start, delimiters) orelse return null;
    const cp = buffer.codePointAt(mid) catch return null;

    if (utils.atLeastOneIsEqual(u21, &white_space, cp)) {
        const end = 1 + (findOutsideBlackList(buffer, mid, &white_space) orelse return null);
        buffer.validateRange(start, end) catch unreachable;
        return .{ .start = start, .end = end };
    } else {
        buffer.validateRange(start, mid) catch unreachable;
        return .{ .start = start, .end = mid + 1 };
    }
}

/// The way a motion works is as follows:
/// Find one of the delimiters and stop there and return.
/// If the starting point is one of the delimiters then move one character and return
/// White space is always ignored
pub fn backward(buffer: *Buffer, index: u64, delimiters: []const u21) ?Range {
    if (index == 0) return null;

    const end = index;
    const end_cp = buffer.codePointAt(end) catch return null;
    const real_end = end + (unicode.utf8CodepointSequenceLength(end_cp) catch return null);

    {
        if (utils.atLeastOneIsEqual(u21, delimiters, end_cp) and !utils.atLeastOneIsEqual(u21, &white_space, end_cp)) {
            var start = end - 1;
            while (utf8.byteType(buffer.lines.byteAt(start)) == .continue_byte and start > 0)
                start -= 1;

            buffer.validateRange(start, real_end) catch unreachable;
            return .{ .start = start, .end = real_end };
        }
    }

    const mid = backFindCodePointsInList(buffer, end, delimiters) orelse return null;
    const cp = buffer.codePointAt(mid) catch return null;

    if (utils.atLeastOneIsEqual(u21, &white_space, cp)) {
        const start = backFindOutsideBlackList(buffer, mid, &white_space) orelse return null;
        buffer.validateRange(start, real_end) catch unreachable;
        return .{ .start = start, .end = real_end };
    } else {
        buffer.validateRange(mid, end) catch unreachable;
        return .{ .start = mid, .end = real_end };
    }
}

pub fn textObject(buffer: *Buffer, index: u64, delimators: []const u21) ?Range {
    const cp_at_cursor = buffer.codePointAt(index) catch return null;

    const start = if (utils.atLeastOneIsEqual(u21, delimators, cp_at_cursor))
        index
    else
        backFindCodePointsInList(buffer, index, delimators) orelse return null;

    const end = findCodePointsInList(buffer, index, delimators) orelse return null;

    return .{ .start = start, .end = end + 1 };
}

pub fn endOfLine(buffer: *Buffer, index:u64) Range {
    const row = buffer.getRowAndCol(index).row;
    return .{ .start = index, .end = buffer.indexOfLastByteAtRow(row) + 1 };
}

pub fn startOfLine(buffer: *Buffer, index:u64) Range {
    const row = buffer.getRowAndCol(index).row;
    return .{ .start = buffer.indexOfFirstByteAtRow(row), .end = index + 1 };
}

pub fn firstLine(buffer: *Buffer, index:u64) Range {
    _ = buffer;
    return .{ .start = 0, .end = index + 1 };
}

pub fn lastLine(buffer: *Buffer, index:u64) Range {
    return .{ .start = index, .end = buffer.size() };
}

pub fn findCP(buffer: *Buffer, cp: u21, index:u64) Range {
    const end = findCodePointsInList(buffer, index, &.{cp});
    return .{ .start = index, .end = end + 1 };
}

pub fn backFindCP(buffer: *Buffer, cp: u21, index:u64) Range {
    const start = backFindCodePointsInList(buffer, index, &.{cp});
    return .{ .start = start, .end = index + 1 };
}
