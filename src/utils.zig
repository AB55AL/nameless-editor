const std = @import("std");

pub fn countChar(string: []const u8, char: u8) u32 {
    var count: u32 = 0;
    for (string) |c| {
        if (c == char) count += 1;
    }
    return count;
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
