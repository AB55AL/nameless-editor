const std = @import("std");
const print = std.debug.print;

pub const two_byte_mask = 0b110_00000;
pub const three_byte_mask = 0b1110_0000;
pub const four_byte_mask = 0b11110_000;
pub const cont_byte_mask = 0b10_000000;

pub const UTF8Error = error{
    invalid_first_byte,
};

pub const CodeUnitType = enum {
    one_byte,
    two_byte,
    three_byte,
    four_byte,
    cont_byte,
};

pub const RangeInArray = struct {
    start: usize,
    end: usize,
};

/// Encodes a Unicode code point as UTF-8 and writes the result to the provided out_buffer
/// Returns how many bytes have been written to the buffer
pub fn encodeToBuffer(code_point: u32, out_buffer: []u8) u8 {
    var first_byte: u8 = 0;
    var second_byte: u8 = 0;
    var third_byte: u8 = 0;
    var forth_byte: u8 = 0;

    var bits = bitsNeededToEncode(code_point);
    var cp = code_point;

    if (bits <= 8) {
        first_byte = @intCast(u8, code_point);

        out_buffer[0] = first_byte;
        return 1;
    } else if (bits <= 16) {
        second_byte = @intCast(u8, cp & 0x3F) | cont_byte_mask;
        cp >>= 6;
        first_byte = @intCast(u8, cp & 0x1F) | two_byte_mask;

        out_buffer[0] = first_byte;
        out_buffer[1] = second_byte;
        return 2;
    } else if (bits <= 24) {
        third_byte = @intCast(u8, cp & 0x3F) | cont_byte_mask;
        cp >>= 6;
        second_byte = @intCast(u8, cp & 0x3F) | cont_byte_mask;
        cp >>= 6;
        first_byte = @intCast(u8, cp & 0x0F) | three_byte_mask;

        out_buffer[0] = first_byte;
        out_buffer[1] = second_byte;
        out_buffer[2] = third_byte;
        return 3;
    } else {
        forth_byte = @intCast(u8, cp & 0x3F) | cont_byte_mask;
        cp >>= 6;
        third_byte = @intCast(u8, cp & 0x3F) | cont_byte_mask;
        cp >>= 6;
        second_byte = @intCast(u8, cp & 0x3F) | cont_byte_mask;
        cp >>= 6;
        first_byte = @intCast(u8, cp & 0x07) | four_byte_mask;

        out_buffer[0] = first_byte;
        out_buffer[1] = second_byte;
        out_buffer[2] = third_byte;
        out_buffer[3] = forth_byte;
        return 4;
    }
}

/// Encodes a Unicode code point as UTF-8 and returns an array containing the bytes.
/// The size of the array is the same as the given size paramater
pub fn encodeGivenSize(comptime size: u8, code_point: u32) [size]u8 {
    if (size > 4 or size <= 0) @compileError("size provided to encodeGivenSize() needs to be between 1 and 4 (inclusive)");

    if (size == 1) {
        var bytes: [1]u8 = undefined;
        _ = encodeToBuffer(code_point, &bytes);
        return bytes;
    } else if (size == 2) {
        var bytes: [2]u8 = undefined;
        _ = encodeToBuffer(code_point, &bytes);
        return bytes;
    } else if (size == 3) {
        var bytes: [3]u8 = undefined;
        _ = encodeToBuffer(code_point, &bytes);
        return bytes;
    } else {
        var bytes: [4]u8 = undefined;
        _ = encodeToBuffer(code_point, &bytes);
        return bytes;
    }
}

pub fn decode(bytes: []const u8) UTF8Error!u32 {
    if (bytes[0] & 0b11_000000 == cont_byte_mask) return UTF8Error.invalid_first_byte;

    var code_point: u32 = 0;

    if (bytes.len == 1) {
        code_point = bytes[0];
    } else if (bytes.len == 2) {
        code_point = bytes[0] & 0x1F;
        code_point <<= 6;
        code_point |= bytes[1] & 0x3F;
    } else if (bytes.len == 3) {
        code_point = bytes[0] & 0x0F;
        code_point <<= 6;
        code_point |= bytes[1] & 0x3F;
        code_point <<= 6;
        code_point |= bytes[2] & 0x3F;
    } else if (bytes.len == 4) {
        code_point = bytes[0] & 0x07;
        code_point <<= 6;
        code_point |= bytes[1] & 0x3F;
        code_point <<= 6;
        code_point |= bytes[2] & 0x3F;
        code_point <<= 6;
        code_point |= bytes[3] & 0x3F;
    }

    return code_point;
}

pub fn bitsNeededToEncode(code_point: u32) u8 {
    return @bitSizeOf(u32) - @clz(u32, code_point);
}

/// Given a valid UTF-8 sequence returns a slice
/// containing the bytes of the ith character up to and including the jth character
pub fn substringOfUTF8Sequence(utf8_seq: []u8, i: usize, j: usize) []u8 {
    if (i == j) {
        var start = firstByteOfCodeUnit(utf8_seq, i);
        var end = sizeOfCodeUnit(utf8_seq[start]);
        return utf8_seq[start .. start + end];
    }

    var start = firstByteOfCodeUnit(utf8_seq, i);
    const seq_after_start = utf8_seq[start..];

    const new_j = j - (utf8_seq.len - seq_after_start.len);

    // const new_j = if (j < utf8_seq.len)
    //     j - (utf8_seq.len - seq_after_start.len)
    // else
    //     utf8_seq.len;
    var end = lastByteOfCodeUnit(seq_after_start, new_j);

    return utf8_seq[start .. end + 1];
}

/// Returns the index (0-based) of the first byte and last byte of the ith character (1-based) in a UTF-8 encoded array
pub fn rangeOfUTF8Char(utf8_string: []const u8, index: usize) RangeInArray {
    var start = firstByteOfCodeUnit(utf8_string, index);
    var end = start + (sizeOfCodeUnit(utf8_string[start]) - 1);

    return .{ .start = start, .end = end };
}

/// Returns a slice of first and last bytes of the ith character (1-based) in a UTF-8 encoded array
pub fn sliceOfUTF8Char(utf8_string: []u8, index: usize) []u8 {
    var start = firstByteOfCodeUnit(utf8_string, index);
    var end = start + (sizeOfCodeUnit(utf8_string[start]));

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
    return i + sizeOfCodeUnit(utf8_string[i]) - 1;
}

/// Returns the number of characters in a UTF-8 sequence
pub fn numOfChars(utf8_seq: []const u8) usize {
    var count: usize = 0;
    for (utf8_seq) |byte| {
        if (typeOfCodeUnit(byte) != CodeUnitType.cont_byte) count += 1;
    }
    return count;
}

pub fn typeOfCodeUnit(byte: u8) CodeUnitType {
    if (byte & 0b1_0000000 == 0) {
        return CodeUnitType.one_byte;
    } else if (byte & 0b111_00000 == two_byte_mask) {
        return CodeUnitType.two_byte;
    } else if (byte & 0b1111_0000 == three_byte_mask) {
        return CodeUnitType.three_byte;
    } else if (byte & 0b11111_000 == four_byte_mask) {
        return CodeUnitType.four_byte;
    } else {
        return CodeUnitType.cont_byte;
    }
}

pub fn sizeOfCodeUnit(byte: u8) u8 {
    var type_of_code_unit = typeOfCodeUnit(byte);

    switch (type_of_code_unit) {
        CodeUnitType.one_byte => {
            return 1;
        },
        CodeUnitType.two_byte => {
            return 2;
        },
        CodeUnitType.three_byte => {
            return 3;
        },
        CodeUnitType.four_byte => {
            return 4;
        },
        CodeUnitType.cont_byte => {
            return 0;
        },
    }
}
