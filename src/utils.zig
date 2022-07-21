const std = @import("std");
const print = std.debug.print;

const utf8 = @import("utf8.zig");

pub fn countChar(string: []const u8, char: u8) u32 {
    var count: u32 = 0;
    for (string) |c| {
        if (c == char) count += 1;
    }
    return count;
}

/// Returns the index (0-based) of the ith (1-based) newline character in a string or
/// 0 if index is 0 or null if it doesn't find it
pub fn getNewline(string: []const u8, index: usize) ?usize {
    if (index == 0) return 0;

    var count: u32 = 0;
    for (string) |c, i| {
        if (c == '\n') {
            count += 1;
            if (count == index)
                return i;
        }
    }

    return null;
}

pub const NewlineLocations = struct {
    first: usize,
    second: usize,
};

/// Returns the indices (0-based) of the ith and jth (1-based) newline characters in a string or
/// null if it doesn't find either i or j
pub fn getNewlines(string: []const u8, i: usize, j: usize) ?NewlineLocations {
    if (i == 0 or j == 0) return null;
    var lines = NewlineLocations{ .first = 0, .second = 0 };

    var count: u32 = 0;
    for (string) |c, index| {
        if (c == '\n') {
            count += 1;

            if (count == i)
                lines.first = index
            else if (count == j) {
                lines.second = index;
                return lines;
            }
        }
    }

    return null;
}

/// Returns a slice from the *i*th row till the *j*th row. (inclusive).
/// If *i* is found and *j* hasn't been found then the slice is from the
/// first byte of the *i*th row to the end of the string
pub fn getLines(string: []const u8, i: usize, j: usize) []const u8 {
    var first_newline = getNewline(string, i - 1).?;
    if (i > 1) first_newline += 1;
    var second_newline = getNewline(string, j);

    if (second_newline) |snl| {
        return string[first_newline .. snl + 1];
    } else {
        return string[first_newline..];
    }
}

/// Given a string, returns a slice of the *i*th line (1-based)
/// A line is:
/// A: The bytes between two newline chars including the second newline char or
/// B: The bytes from the start of the string up to and including the first newline char or
/// C: If there's no newline chars the line is the provided string
pub fn getLine(string: []const u8, index: usize) []const u8 {
    if (index == 1) {
        const from = 0;
        const to = getNewline(string, 1) orelse string.len - 1;

        return string[from .. to + 1];
    } else if (getNewlines(string, index - 1, index)) |nl| {
        const from = nl.first + 1;
        const to = nl.second + 1;

        return string[from..to];
    } else {
        return string;
    }
}

/// Translates 2D indices to 1D in a string.
/// Returns the index of the first byte of a UTF-8 sequence in the
/// string at *row* and *col*
pub fn getIndex(string: []const u8, row: u32, col: u32) usize {
    if (row == 1) {
        return utf8.firstByteOfCodeUnit(string, col);
    }

    const line = getNewline(string, row - 1);
    var index: usize = if (line) |l| l + 1 else 0;

    const slice = getLine(string, row);
    index += utf8.firstByteOfCodeUnit(slice, col);

    return index;
}

pub fn splitAfter(comptime T: type, buffer: []const T, delimiter: T) SplitAfterIterator(T) {
    return .{
        .buffer = buffer,
        .start_index = 0,
        .end_index = 0,
        .delimiter = delimiter,
    };
}

pub fn SplitAfterIterator(comptime T: type) type {
    return struct {
        buffer: []const T,
        start_index: usize,
        end_index: usize,
        delimiter: T,

        const Self = @This();

        /// Returns a slice of the next field, or null if splitting is complete.
        pub fn next(self: *Self) ?[]const T {
            var i: usize = self.start_index;
            while (i < self.buffer.len) {
                var element = self.buffer[i];
                if (element == self.delimiter or i == self.buffer.len - 1) {
                    const s = std.math.min(self.start_index, self.buffer.len);
                    const e = std.math.min(self.end_index + 1, self.buffer.len);
                    var slice = self.buffer[s..e];

                    self.end_index += 1;
                    self.start_index = self.end_index;
                    return slice;
                } else {
                    self.end_index += 1;
                    i += 1;
                }
            }
            return null;
        }
    };
}

/// Takes three numbers and returns true if the first number is in the range
/// of the second and third numbers
pub fn inRange(comptime T: type, a: T, b: T, c: T) bool {
    return a >= b and a <= c;
}
