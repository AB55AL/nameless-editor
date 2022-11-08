const std = @import("std");
const print = std.debug.print;
const eql = std.mem.eql;

const vectors = @import("vectors.zig");

pub fn hexToColorVector(hex: u24) vectors.vec3 {
    var r = (1.0 / 255.0) * @intToFloat(f32, hex >> 16);
    var g = (1.0 / 255.0) * @intToFloat(f32, (hex >> 8) & 0xFF);
    var b = (1.0 / 255.0) * @intToFloat(f32, hex & 0xFF);
    return .{ .x = r, .y = g, .z = b };
}
