const std = @import("std");
const print = std.debug.print;

const utf8 = @import("utf8.zig");

pub fn assert(ok: bool, comptime message: []const u8) void {
    if (!ok) {
        print("{s}\n", .{message});
        unreachable;
    }
}

/// Takes three numbers and returns true if the first number is in the range
/// of the second and third numbers
pub fn inRange(a: anytype, b: @TypeOf(a), c: @TypeOf(a)) bool {
    return a >= b and a <= c;
}

pub fn abs(val: f32) f32 {
    return if (val < 0) -val else val;
}

pub fn fileLocation(comptime location: std.builtin.SourceLocation) []const u8 {
    return location.file ++ " | " ++ location.fn_name ++ ": ";
}

pub fn atLeastOneIsEqual(comptime T: type, slice: []const T, value: T) bool {
    for (slice) |v| if (v == value) return true;
    return false;
}
