const std = @import("std");
const print = std.debug.print;

pub const Cursor = @This();

row: i32,
col: i32,

pub fn init() Cursor {
    return Cursor{
        .row = 1,
        .col = 1,
    };
}
