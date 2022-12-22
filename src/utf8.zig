const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const assert = std.debug.assert;

pub const ByteType = enum {
    start_byte,
    continue_byte,
};

/// Given a valid UTF-8 sequence returns a slice
/// containing the bytes of the ith character up to and including the jth character (1-based)
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
pub fn firstByteOfCodeUnit(utf8_seq: []const u8, index: usize) usize {
    assert(utf8_seq.len > 0);

    var byte_index: usize = 0;
    var char_count: usize = 0;
    var i: usize = 0;
    while (i < utf8_seq.len) {
        if (char_count >= index) break;

        const byte = utf8_seq[i];
        const byte_seq_len = unicode.utf8ByteSequenceLength(byte) catch 0;
        if (byte_seq_len > 0) {
            char_count += 1;
            byte_index = i;
            i += byte_seq_len;
        } else { // Continuation byte
            i += 1;
        }
    }

    return byte_index;
}

/// Returns the index (0-based) of the first byte of the ith character (1-based) in a UTF-8 encoded array.
/// If the function encounters a newline byte it will return it's index
/// Asserts *utf8_seq.len* > 0
pub fn firstByteOfCodeUnitUpToNewline(utf8_seq: []const u8, index: usize) usize {
    if (utf8_seq.len == 0) return 0;

    var byte_index: usize = 0;
    var char_count: usize = 0;
    var i: usize = 0;
    while (i < utf8_seq.len) {
        if (char_count >= index) break;

        const byte = utf8_seq[i];
        const byte_seq_len = unicode.utf8ByteSequenceLength(byte) catch 0;
        if (byte == '\n') {
            byte_index = i;
            break;
        } else if (byte_seq_len > 0) {
            char_count += 1;
            byte_index = i;
            i += byte_seq_len;
        } else { // Continuation byte
            i += 1;
        }
    }

    return byte_index;
}

/// Returns the index (0-based) of the last byte of the ith character (1-based) in a UTF-8 encoded array
pub fn lastByteOfCodeUnit(utf8_string: []const u8, index: usize) usize {
    var i = firstByteOfCodeUnit(utf8_string, index);
    var len = unicode.utf8ByteSequenceLength(utf8_string[i]) catch unreachable;
    return i + len - 1;
}

pub fn byteType(byte: u8) ByteType {
    return switch (byte) {
        0b0000_0000...0b0111_1111, // ASCII
        0b1100_0000...0b1101_1111, // 2-byte UTF-8
        0b1110_0000...0b1110_1111, // 3-byte UTF-8
        0b1111_0000...0b1111_0111, // 4-byte UTF-8
        => return .start_byte,

        else => return .continue_byte,
    };
}