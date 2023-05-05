const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const unicode = std.unicode;

const indexOf = std.mem.indexOf;

const BufferWindow = @import("../editor/buffer_window.zig").BufferWindow;
const Buffer = @import("../editor/buffer.zig");
const BufferIterator = Buffer.BufferIterator;
const ReverseBufferIterator = Buffer.ReverseBufferIterator;
const Point = Buffer.Point;
const utils = @import("../utils.zig");
const utf8 = @import("../utf8.zig");

pub const white_space = blk: {
    var ws: [std.ascii.whitespace.len]u21 = undefined;
    for (std.ascii.whitespace, 0..) |c, i| ws[i] = c;
    break :blk ws;
};

// pub const word_delimitors = white_space ++ .{ 'c', '@' };
pub const word_delimitors = white_space;

fn getSubLine(buffer: *Buffer, buf: []u8, start: Point) []u8 {
    const s = buffer.getIndex(start);
    const e = buffer.indexOfLastByteAtRow(start.row) + 1;
    var iter = BufferIterator.init(buffer, s, e);

    var i: u64 = 0;
    while (iter.next()) |string| {
        std.mem.copy(u8, buf[i..], string);
        i += string.len;
    }

    return buf[0..i];
}

pub fn findCodePointsInList(buffer: *Buffer, start: Point, list: []const u21) ?Point {
    const start_index = buffer.getIndex(start);
    var iter = BufferIterator.init(buffer, start_index, buffer.size());

    var i: u64 = start_index;
    while (iter.next()) |string| {
        var uiter = utf8.Utf8Iterator{ .bytes = string };
        while (uiter.nextCodepointSlice()) |slice| {
            defer i += slice.len;
            const cp = unicode.utf8Decode(slice) catch continue;
            if (utils.atLeastOneIsEqual(u21, list, cp)) {
                return buffer.getPoint(i);
            }
        }
    }

    return null;
}

pub fn findOutsideBlackList(buffer: *Buffer, start: Point, black_list: []const u21) ?Point {
    const start_index = buffer.getIndex(start);
    var iter = BufferIterator.init(buffer, start_index, buffer.size());

    var i: u64 = start_index;
    while (iter.next()) |string| {
        var uiter = utf8.Utf8Iterator{ .bytes = string };
        while (uiter.nextCodepointSlice()) |slice| {
            defer i += slice.len;
            const cp = unicode.utf8Decode(slice) catch continue;
            if (!utils.atLeastOneIsEqual(u21, black_list, cp)) {
                return buffer.getPoint(i);
            }
        }
    }

    return null;
}

pub fn backFindCodePointsInList(buffer: *Buffer, start: Point, list: []const u21) ?Point {
    if (std.meta.eql(start, .{ .row = 1, .col = 1 })) return null;
    const start_index = buffer.getIndex(start);
    var iter = ReverseBufferIterator.init(buffer, 0, start_index);

    var index = start_index;
    while (iter.next()) |string| {
        var view = utf8.ReverseUtf8View(string);
        while (view.prevSlice()) |slice| {
            defer index -|= slice.len;

            const cp = unicode.utf8Decode(slice) catch continue;
            if (utils.atLeastOneIsEqual(u21, list, cp))
                return buffer.getPoint(index);
        }
    }

    return null;
}

pub fn backFindOutsideBlackList(buffer: *Buffer, start: Point, list: []const u21) ?Point {
    if (std.meta.eql(start, .{ .row = 1, .col = 1 })) return null;
    const start_index = buffer.getIndex(start);
    var iter = ReverseBufferIterator.init(buffer, 0, start_index);

    var index = start_index;
    while (iter.next()) |string| {
        var view = utf8.ReverseUtf8View(string);
        while (view.prevSlice()) |slice| {
            defer index -|= slice.len;

            const cp = unicode.utf8Decode(slice) catch continue;
            if (!utils.atLeastOneIsEqual(u21, list, cp))
                return buffer.getPoint(index);
        }
    }

    return null;
}

/// The way a motion works is as follows:
/// Find one of the delimiters and stop there and return.
/// If the starting point is one of the delimiters then move one character and return
/// White space is always ignored
pub fn forward(buffer: *Buffer, start: Point, delimiters: []const u21) ?Buffer.PointRange {
    var cp = buffer.codePointAt(buffer.getIndex(start)) catch return null;
    if (utils.atLeastOneIsEqual(u21, delimiters, cp) and !utils.atLeastOneIsEqual(u21, &white_space, cp))
        return .{ .start = start, .end = start.addCol(1) };

    const mid = findCodePointsInList(buffer, start.addCol(1), delimiters) orelse return null;
    const end = findOutsideBlackList(buffer, mid, &white_space) orelse mid;
    return .{ .start = start, .end = end };
}

//// The way a motion works is as follows:
//// Find one of the delimiters and stop there and return.
//// If the starting point is one of the delimiters then move one character and return
//// White space is always ignored
pub fn backward(buffer: *Buffer, start: Point, delimiters: []const u21) ?Buffer.PointRange {
    if (std.meta.eql(start, .{ .row = 1, .col = 1 })) return null;

    var cp = buffer.codePointAt(buffer.getIndex(start)) catch return null;
    if (utils.atLeastOneIsEqual(u21, delimiters, cp) and !utils.atLeastOneIsEqual(u21, &white_space, cp))
        return .{ .start = start.subCol(1), .end = start };

    const mid = backFindCodePointsInList(buffer, start, delimiters) orelse Point{ .row = 1, .col = 1 };
    const s = backFindOutsideBlackList(buffer, mid, &white_space) orelse mid;
    return .{ .start = s, .end = start };
}

pub fn innerTextObject(buffer: *Buffer, start: Point, delimators: []const u21) ?Buffer.PointRange {
    var range = aroundTextObject(buffer, start, delimators) orelse return null;
    return .{ .start = range.start.addCol(1), .end = range.end.subCol(1) };
}

pub fn aroundTextObject(buffer: *Buffer, start: Point, delimators: []const u21) ?Buffer.PointRange {
    const s = backFindCodePointsInList(buffer, start, delimators) orelse return null;
    const e = findCodePointsInList(buffer, start.addCol(1), delimators) orelse return null;
    return .{ .start = s, .end = e };
}

pub fn endOfLine(buffer: *Buffer, point: Point) Buffer.PointRange {
    _ = buffer;
    return .{ .start = point, .end = point.setCol(Point.last_col) };
}

pub fn startOfLine(buffer: *Buffer, point: Point) Buffer.PointRange {
    _ = buffer;
    return .{ .start = point.setCol(1), .end = point };
}

pub fn firstLine(buffer: *Buffer, point: Point) Buffer.PointRange {
    _ = buffer;
    return .{ .start = .{ .row = 1, .col = 1 }, .end = point };
}

pub fn lastLine(buffer: *Buffer, point: Point) Buffer.PointRange {
    return .{ .start = point, .end = .{ .row = buffer.lineCount(), .col = Point.last_col } };
}

pub fn findCP(buffer: *Buffer, cp: u21, point: Point) Buffer.PointRange {
    const end = findCodePointsInList(buffer, point, &.{cp});
    return .{ .start = point, .end = end };
}

pub fn backFindCP(buffer: *Buffer, cp: u21, point: Point) Buffer.PointRange {
    const start = backFindCodePointsInList(buffer, point, &.{cp});
    return .{ .start = start, .end = point };
}
