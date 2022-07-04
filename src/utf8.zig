const std = @import("std");
const print = std.debug.print;

/// Returns the index (0-based) of first byte of the ith character (1-based) in a utf-8 string
pub fn arrayIndexOfCodePoint(utf8_string: []const u8, index: usize) usize {
    var i: usize = 0;
    var char: usize = 0;
    for (utf8_string) |byte, byte_index| {
        if (char >= index) break;
        if (byte & 0b11_000000 != 0b10_000000 or byte & 0b10000000 == 0) {
            char += 1;
            i = byte_index;
        }
    }
    return i;
}
