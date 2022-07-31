const std = @import("std");
const print = std.debug.print;
const eql = std.mem.eql;

const vectors = @import("vectors.zig");

pub fn getColor(string: []const u8) vectors.vec3 {
    if (isKeyWord(string)) return hexToColorVector(0xF92672) else return .{ .x = 1, .y = 1, .z = 1 };
}

pub fn hexToColorVector(hex: u24) vectors.vec3 {
    var r = (1.0 / 255.0) * @intToFloat(f32, hex >> 16);
    var g = (1.0 / 255.0) * @intToFloat(f32, (hex >> 8) & 0xFF);
    var b = (1.0 / 255.0) * @intToFloat(f32, hex & 0xFF);
    return .{ .x = r, .y = g, .z = b };
}

fn isKeyWord(string: []const u8) bool {
    return manyEql(string, &[_][]const u8{
        "var",
        "const",
        "if",
        "fn",
        "for",
        "break",
        "catch",
        "comptime",
        "continue",
        "defer",
        "else",
        "enum",
        "while",
        "and",
        "error",
        "errdefer",
        "or",
        "orelse",
        "pub",
        "return",
        "struct",
        "switch",
        "try",
        "union",
        "unreachable",

        "align",
        "allowzero",
        "anyframe",
        "anytype",
        "asm",
        "async",
        "await",
        "export",
        "extern",
        "inline",
        "noalias",
        "nosuspend",
        "packed",
        "resume",
        "linksection",
        "suspend",
        "test",
        "threadlocal",
        "usingnamespace",
        "volatile",
    });
}

fn manyEql(string: []const u8, strings: []const []const u8) bool {
    @setRuntimeSafety(false);
    for (strings) |str|
        if (eql(u8, string, str)) return true;

    return false;
}
