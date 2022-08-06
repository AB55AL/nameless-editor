const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
// const Buffer = @import("editor/buffer.zig");
// const renderer = @import("ui/renderer.zig");
// const Window = @import("ui/window.zig").Window;
// const command_line = @import("editor/command_line.zig");
const glfw_window = @import("ui/glfw.zig");
// const buffer_ops = @import("editor/buffer_ops.zig");
const globals = @import("globals.zig");
// const layouts = @import("ui/layouts.zig");

// const input_layer = @import("input_layer");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    defer _ = gpa.deinit();

    const window_width: u32 = 800;
    const window_height: u32 = 600;

    try globals.initGlobals(gpa.allocator(), window_width, window_height);
    defer globals.deinitGlobals();

    var window = try glfw_window.init(window_width, window_height);
    defer glfw_window.deinit(&window);

    // var lib = try std.DynLib.open("zig-out/lib/libmain2.so");
    // _ = lib;
    // const main2 = lib.lookup(*anyopaque, "main2");
    // _ = main2;

    // if (main2) |void_func| {
    //     const f = @ptrCast(fn (*bool) void, void_func);
    //     f(globals.global.command_line_is_open);
    // }
}
