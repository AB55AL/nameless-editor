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
    options: WindowOptions = .{},
};
