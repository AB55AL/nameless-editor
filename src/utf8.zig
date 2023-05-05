const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const assert = std.debug.assert;

const utils = @import("utils.zig");

pub const ByteType = enum {
    start_byte,
    continue_byte,
};

pub fn byteType(byte: u8) ByteType {
    const result = unicode.utf8ByteSequenceLength(byte);
    return if (result == error.Utf8InvalidStartByte) .continue_byte else .start_byte;
}

/// Counts the number of code points in a string. When an invalid byte is encountered
/// it is counted as one code point.
pub fn countCodepoints(string: []const u8) u64 {
    var count: u64 = 0;
    var i: u64 = 0;
    while (i < string.len) {
        var byte = string[i];

        var len = unicode.utf8ByteSequenceLength(byte) catch 1;
        i += len;
        count += 1;
    }

    return count;
}

/// Finds the index of the *nth* code point in a string. When an invalid byte is encountered
/// it is counted as one code point.
pub fn indexOfCP(string: []const u8, cp: u64) u64 {
    assert(cp > 0);

    var count: u64 = 0;
    var i: u64 = 0;
    while (i < string.len) {
        var byte = string[i];
        var len = unicode.utf8ByteSequenceLength(byte) catch 1;
        count += 1;
        if (cp == count) return i;
        i += len;
    }

    return i;
}

pub const Utf8Iterator = struct {
    const Self = @This();

    bytes: []const u8,
    i: usize = 0,

    pub fn nextCodepointSlice(it: *Self) ?[]const u8 {
        if (it.i >= it.bytes.len) {
            return null;
        }

        const cp_len = unicode.utf8ByteSequenceLength(it.bytes[it.i]) catch 1;
        it.i += cp_len;
        return it.bytes[it.i - cp_len .. it.i];
    }
};

pub fn ReverseUtf8View(string: []const u8) ReverseUtf8ViewType {
    return .{
        .string = string,
        .index = string.len,
    };
}

pub const ReverseUtf8ViewType = struct {
    const Self = @This();
    string: []const u8,
    index: u64,
    done: bool = false,

    pub fn prevSlice(self: *Self) ?[]const u8 {
        if (self.done) return null;
        var i: u64 = self.index -| 1;
        utils.assert(byteType(self.string[i]) == .continue_byte or self.string[i] <= 256, "Must start at a continue byte or an ASCII char for reverse iteration");

        var byte = self.string[i];
        var cont_bytes: u4 = 0;
        while (byteType(byte) == .continue_byte and i >= 0) {
            i -|= 1;
            byte = self.string[i];
            cont_bytes += 1;
        }

        utils.assert(cont_bytes <= 3, "");

        const end = self.index;
        if (i == 0) self.done = true;
        self.index = i;
        return self.string[i..end];
    }

    pub fn prevCodePoint(self: *Self) ?u21 {
        const slice = self.prevSlice() orelse return null;
        return unicode.utf8Decode(slice) catch unreachable;
    }
};
