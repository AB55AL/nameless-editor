const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const Buffer = @import("editor/buffer.zig");
const command_line = @import("editor/command_line.zig");
const glfw_window = @import("ui/glfw.zig");
const buffer_ops = @import("editor/buffer_ops.zig");
const globals = @import("globals.zig");

const input_layer = @import("input_layer");
const options = @import("options");
const user = @import("user");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    defer _ = gpa.deinit();

    const window_width: u32 = 800;
    const window_height: u32 = 600;

    try globals.initGlobals(gpa.allocator(), window_width, window_height);
    defer globals.deinitGlobals();

    var window = try glfw_window.init(window_width, window_height);
    defer glfw_window.deinit(&window);

    try input_layer.init();
    defer input_layer.deinit();

    try command_line.init();
    defer command_line.deinit();

    if (globals.global.first_buffer == null) {
        var buffer = try buffer_ops.createPathLessBuffer();
        globals.global.focused_buffer = buffer;
        _ = try buffer_ops.openBufferI(buffer.index);
    }

    if (options.user_config_loaded) try user.init();
    defer if (options.user_config_loaded) user.deinit();

    while (!window.shouldClose()) {
        if (globals.global.valid_buffers_count == 0) window.setShouldClose(true);
        try glfw.pollEvents();
    }
}
