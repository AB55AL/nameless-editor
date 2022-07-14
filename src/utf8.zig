const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;

/// Given a valid UTF-8 sequence returns a slice
/// containing the bytes of the ith character up to and including the jth character
pub fn substringOfUTF8Sequence(utf8_seq: []const u8, i: usize, j: usize) ![]const u8 {
    if (i == j) {
        var start = firstByteOfCodeUnit(utf8_seq, i);
        var end = try unicode.utf8ByteSequenceLength(utf8_seq[start]);
        return utf8_seq[start .. start + end];
    }

    var start = firstByteOfCodeUnit(utf8_seq, i);
    var end = lastByteOfCodeUnit(utf8_seq, j);

    return utf8_seq[start .. end + 1];
}

/// Returns a slice of first and last bytes of the ith character (1-based) in a UTF-8 encoded array
pub fn sliceOfUTF8Char(utf8_string: []const u8, index: usize) ![]const u8 {
    var start = firstByteOfCodeUnit(utf8_string, index);
    var len = try unicode.utf8ByteSequenceLength(utf8_string[start]);
    var end = start + len;

    return utf8_string[start..end];
}

/// Returns the index (0-based) of the first byte of the ith character (1-based) in a UTF-8 encoded array
pub fn firstByteOfCodeUnit(utf8_string: []const u8, index: usize) usize {
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

/// Returns the index (0-based) of the last byte of the ith character (1-based) in a UTF-8 encoded array
pub fn lastByteOfCodeUnit(utf8_string: []const u8, index: usize) usize {
    var i = firstByteOfCodeUnit(utf8_string, index);
    var len = unicode.utf8ByteSequenceLength(utf8_string[i]) catch unreachable;
    return i + len - 1;
}
