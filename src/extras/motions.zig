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

pub fn findCodePointsInList(buffer: *Buffer, start: u64, list: []const u21) ?u64 {
    var offset = unicode.utf8ByteSequenceLength(buffer.lines.byteAt(start)) catch return null;
    var iter = BufferIterator.init(buffer, start + offset, buffer.size());
    var previous_strings_len = start + offset;
    while (iter.next()) |string| {
        defer previous_strings_len += string.len;
        var view = unicode.Utf8View.initUnchecked(string).iterator();
        while (view.nextCodepoint()) |cp| {
            if (utils.atLeastOneIsEqual(u21, list, cp))
                return previous_strings_len + view.i -| 1;
        }
    }

    return null;
}

pub fn findOutsideBlackList(buffer: *Buffer, start: u64, black_list: []const u21) ?u64 {
    var offset = unicode.utf8ByteSequenceLength(buffer.lines.byteAt(start)) catch return null;
    var iter = BufferIterator.init(buffer, start + offset, buffer.size());
    var previous_strings_len = start + offset;
    while (iter.next()) |string| {
        defer previous_strings_len += string.len;
        var view = unicode.Utf8View.initUnchecked(string).iterator();

        var i = view.i;
        while (view.nextCodepoint()) |cp| {
            defer i = view.i;
            if (!utils.atLeastOneIsEqual(u21, black_list, cp)) {
                return previous_strings_len + i;
            }
        }
    }

    return null;
}

pub fn backFindCodePointsInList(buffer: *Buffer, start: u64, list: []const u21) ?u64 {
    if (start == 0) return null;
    var iter = ReverseBufferIterator.init(buffer, 0, start - 1);

    var next_cp_index: u64 = 0;
    var previous_strings_len = start - 1;
    while (iter.next()) |string| {
        previous_strings_len = if (previous_strings_len <= string.len) 0 else previous_strings_len - string.len;
        var view = utf8.ReverseUtf8View(string);
        while (view.prevCodePoint()) |cp| {
            const abs_index = previous_strings_len + view.index;
            if (utils.atLeastOneIsEqual(u21, list, cp))
                return abs_index + 1;

            next_cp_index = abs_index;
        }
    }

    return null;
}

pub fn backFindOutsideBlackList(buffer: *Buffer, start: u64, list: []const u21) ?u64 {
    if (start == 0) return null;
    var iter = ReverseBufferIterator.init(buffer, 0, start - 1);

    var next_cp_index: u64 = 0;
    var previous_strings_len = start - 1;
    while (iter.next()) |string| {
        previous_strings_len = if (previous_strings_len <= string.len) 0 else previous_strings_len - string.len;
        var view = utf8.ReverseUtf8View(string);
        while (view.prevCodePoint()) |cp| {
            const abs_index = previous_strings_len + view.index;
            if (!utils.atLeastOneIsEqual(u21, list, cp))
                return abs_index + 1;

            next_cp_index = abs_index;
        }
    }

    return null;
}

pub const word = struct {
    const white_space = [_]u21{ ' ', '\n', '\t' };
    pub fn forward(buffer: *Buffer) ?Range {
        const start = buffer.cursor_index;
        const mid = findCodePointsInList(buffer, start, &white_space) orelse return null;
        const end = findOutsideBlackList(buffer, mid, &white_space) orelse return null;

        buffer.validateRange(start, end) catch return null;
        return .{ .start = start, .end = end };
    }

    pub fn backward(buffer: *Buffer) ?Range {
        if (buffer.cursor_index == 0) {
            return null;
        }

        const end = buffer.cursor_index;

        const mid = backFindCodePointsInList(buffer, end, &white_space) orelse return null;
        const start = backFindOutsideBlackList(buffer, mid, &white_space) orelse return null;

        buffer.validateRange(start, end) catch return null;
        return .{ .start = start, .end = end };
    }

    pub fn moveForward(buffer_window: *BufferWindow) void {
        const range = forward(buffer_window.buffer) orelse return;
        buffer_window.buffer.cursor_index = range.end;
    }

    pub fn moveBackwards(buffer_window: *BufferWindow) void {
        const range = backward(buffer_window.buffer) orelse return;
        buffer_window.buffer.cursor_index = range.start;
    }
};
