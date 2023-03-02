const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const assert = std.debug.assert;

const utils = @import("utils.zig");

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
    const result = unicode.utf8ByteSequenceLength(byte);
    return if (result == error.Utf8InvalidStartByte) .continue_byte else .start_byte;
}

pub fn ReverseUtf8View(string: []const u8) ReverseUtf8ViewType {
    return .{
        .string = string,
        .index = if (string.len == 0) 0 else string.len - 1,
    };
}

pub const ReverseUtf8ViewType = struct {
    const Self = @This();
    string: []const u8,
    index: u64,
    done: bool = false,

    pub fn prevSlice(self: *Self) ?[]const u8 {
        if (self.done) return null;
        var i: u64 = self.index;
        utils.assert(byteType(self.string[i]) == .continue_byte or self.string[i] <= 256, "Must start at a continue byte or an ASCII char for reverse iteration");

        var cont_bytes: u3 = 0;
        while (i >= 0) {
            const byte = self.string[i];
            switch (byteType(byte)) {
                .start_byte => {
                    const index = self.index + 1;
                    if (i == 0) self.done = true;
                    self.index = i -| 1;
                    return self.string[i..index];
                },
                .continue_byte => {
                    cont_bytes += 1;
                    i -|= 1;
                },
            }
        }

        return null;
    }

    pub fn prevCodePoint(self: *Self) ?u21 {
        const slice = self.prevSlice() orelse return null;
        return unicode.utf8Decode(slice) catch unreachable;
    }
};
