const std = @import("std");
const print = std.debug.print;

pub const Cursor = struct {
    row: u32,
    col: u32,
};
