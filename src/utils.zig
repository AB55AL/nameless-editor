const std = @import("std");

pub fn splitByLineIterator(string: []const u8) ?[]const u8 {
    const static = struct {
        var start: usize = 0;
        var end: usize = 0;
    };

    var i: usize = static.start;
    while (i < string.len) {
        var char = string[i];
        if (char == '\n' or i == string.len - 1) {
            const s = std.math.min(static.start, string.len);
            const e = std.math.min(static.end + 1, string.len);
            var slice = string[s..e];

            static.end += 1;
            static.start = static.end;
            return slice;
        } else {
            static.end += 1;
            i += 1;
        }
    }

    static.start = 0;
    static.end = 0;
    return null;
}

pub fn countChar(string: []const u8, char: u8) u32 {
    var count: u32 = 0;
    for (string) |c| {
        if (c == char) count += 1;
    }
    return count;
}
