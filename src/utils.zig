const std = @import("std");
const print = std.debug.print;

const utf8 = @import("utf8.zig");

pub fn assert(ok: bool, comptime message: []const u8) void {
    if (!ok) {
        print("{s}\n", .{message});
        unreachable;
    }
}

pub fn passert(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (!ok) {
        print(fmt ++ "\n", args);
        unreachable;
    }
}

pub fn newSlice(allocator: std.mem.Allocator, content: anytype) !@TypeOf(content) {
    const info = @typeInfo(@TypeOf(content));
    if (info != .Pointer or info.Pointer.size != .Slice) @compileError("Expected a slice instead found " ++ @typeName(@TypeOf(content)));
    const T = info.Pointer.child;

    var slice = try allocator.alloc(T, content.len);
    std.mem.copy(T, slice, content);
    return slice;
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

pub fn diff(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if (a >= b) a - b else b - a;
}

pub fn bound(value: anytype, at_least: @TypeOf(value), at_most: @TypeOf(value)) @TypeOf(value) {
    return if (value <= at_least) at_least else if (value >= at_most) at_most else value;
}
