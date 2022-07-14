const std = @import("std");

pub fn countChar(string: []const u8, char: u8) u32 {
    var count: u32 = 0;
    for (string) |c| {
        if (c == char) count += 1;
    }
    return count;
}

/// Returns the index (0-based) of the ith (1-based) newline character in a string or
/// null if it doesn't find it or if the index is 0
pub fn getNewline(string: []const u8, index: usize) ?usize {
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
