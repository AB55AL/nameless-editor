const std = @import("std");
const print = std.debug.print;

pub const Cursor = struct {
    row: i32,
    col: i32,
};
