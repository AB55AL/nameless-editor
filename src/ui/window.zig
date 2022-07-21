const std = @import("std");
const print = std.debug.print;

pub const WindowOptions = struct {
    wrap_text: bool = false,
};

pub const Window = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    start_col: u32 = 0,
    start_row: u32 = 0,
    num_of_rows: u32 = 0,

    options: WindowOptions = .{},
};
