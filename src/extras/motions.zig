const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const unicode = std.unicode;

const BufferWindow = @import("../ui/buffer.zig").BufferWindow;
const Buffer = @import("../editor/buffer.zig");
const Range = Buffer.Range;
const utils = @import("../utils.zig");
const utf8 = @import("../utf8.zig");

pub fn findCodePointsInLists(buffer: *Buffer, start: u64, stop_before: []const u21, stop_at: []const u21, stop_after: []const u21) ?u64 {
    var iter = buffer.BufferIterator(start + 1, buffer.lines.size);
    var previous_strings_len = start;
    var previous_cp_index: u64 = 0;
    while (iter.next()) |string| {
        defer previous_strings_len += string.len;
        var view = unicode.Utf8View.initUnchecked(string).iterator();
        while (view.nextCodepoint()) |cp| {
            const abs_index = previous_strings_len + view.i;
            if (utils.atLeastOneIsEqual(u21, stop_before, cp) and abs_index != 0)
                return previous_cp_index
            else if (utils.atLeastOneIsEqual(u21, stop_at, cp))
                return abs_index
            else if (utils.atLeastOneIsEqual(u21, stop_after, cp) and abs_index < buffer.lines.size - 1)
                return abs_index + (unicode.utf8CodepointSequenceLength(cp) catch unreachable);

            previous_cp_index = abs_index;
        }
    }

    return null;
}

pub fn findOutsideBlackList(buffer: *Buffer, start: u64, black_list: []const u21) ?u64 {
    var iter = buffer.BufferIterator(start + 1, buffer.lines.size);
    var previous_strings_len = start;
    while (iter.next()) |string| {
        defer previous_strings_len += string.len;
        var view = unicode.Utf8View.initUnchecked(string).iterator();
        while (view.nextCodepoint()) |cp| {
            if (!utils.atLeastOneIsEqual(u21, black_list, cp)) {
                return previous_strings_len + view.i;
            }
        }
    }

    return null;
}

pub fn findCodePoint(buffer: *Buffer, start: u64, code_point: u21) ?u64 {
    var iter = buffer.bufferIterator(start + 1, buffer.lines.size);
    var previous_strings_len = start;
    while (iter.next()) |string| {
        defer previous_strings_len += string.len;
        var view = unicode.Utf8View.initUnchecked(string).iterator();
        while (view.nextCodepoint()) |cp|
            if (cp == code_point)
                return previous_strings_len + view.i;
    }

    return null;
}

pub fn backFindCodePointsInLists(buffer: *Buffer, start: u64, stop_before: []const u21, stop_at: []const u21, stop_after: []const u21) ?u64 {
    if (start == 0) return null;
    var iter = buffer.ReverseBufferIterator(0, start - 1);

    var next_cp_index: u64 = 0;
    var previous_strings_len = start - 1;
    while (iter.next()) |string| {
        previous_strings_len = if (previous_strings_len <= string.len) 0 else previous_strings_len - string.len;
        var view = utf8.ReverseUtf8View(string);
        while (view.prevCodePoint()) |cp| {
            const abs_index = previous_strings_len + view.index;

            if (utils.atLeastOneIsEqual(u21, stop_before, cp) and abs_index != 0)
                return abs_index - 1
            else if (utils.atLeastOneIsEqual(u21, stop_at, cp))
                return abs_index + 1
            else if (utils.atLeastOneIsEqual(u21, stop_after, cp) and abs_index < buffer.lines.size - 1)
                return next_cp_index + 1;

            next_cp_index = abs_index;
        }
    }

    return null;
}

pub const word = struct {
    pub fn forward(buffer: *Buffer) Range {
        const start = buffer.cursor_index;
        const list = [_]u21{ ' ', '\n' };
        const end = findCodePointsInLists(buffer, start, &.{}, &.{}, &list) orelse start;
        const real_end = if (utils.atLeastOneIsEqual(u21, &list, buffer.lines.byteAt(end)))
            findOutsideBlackList(buffer, end, &list) orelse end
        else
            end;

        return .{
            .start = start,
            .end = real_end,
        };
    }

    pub fn backward(buffer: *Buffer) Range {
        if (buffer.cursor_index == 0) {
            return .{ .start = 0, .end = 0 };
        }

        const end = buffer.cursor_index;
        const list = [_]u21{ ' ', '\n' };

        if (utils.atLeastOneIsEqual(u21, &list, buffer.lines.byteAt(end - 1))) {
            const start = backFindCodePointsInLists(buffer, end, &.{}, &list, &.{}) orelse end;
            const real_start = backFindCodePointsInLists(buffer, start, &.{}, &.{}, &list) orelse 0;
            return .{ .start = real_start, .end = end };
        } else {
            const start = backFindCodePointsInLists(buffer, end, &.{}, &.{}, &list) orelse 0;
            return .{ .start = start, .end = end };
        }
    }

    pub fn moveForward(buffer_window: *BufferWindow) void {
        const range = forward(buffer_window.buffer);
        buffer_window.buffer.cursor_index = range.end;
        buffer_window.setWindowCursorToBuffer();
    }

    pub fn moveBackwards(buffer_window: *BufferWindow) void {
        const range = backward(buffer_window.buffer);
        buffer_window.buffer.cursor_index = range.start;
        buffer_window.setWindowCursorToBuffer();
    }
};
