const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const c = @import("c.zig");
const Buffer = @import("buffer.zig");
const renderer = @import("ui/renderer.zig");
const command_line = @import("command_line.zig");
const glfw_window = @import("glfw.zig");
const buffer_ops = @import("buffer_operations.zig");

const input_layer = @import("input_layer");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
export var global_allocator = gpa.allocator();

export var focused_buffer: *Buffer = undefined;
export var global_buffers: ArrayList(*Buffer) = undefined;
export var global_buffers_trashcan: ArrayList(*Buffer) = undefined;

pub fn main() !void {
    defer _ = gpa.deinit();
    global_buffers = ArrayList(*Buffer).init(global_allocator);
    global_buffers_trashcan = ArrayList(*Buffer).init(global_allocator);
    defer {
        for (global_buffers.items) |buffer|
            buffer.deinitAndDestroy();
        global_buffers.deinit();

        for (global_buffers_trashcan.items) |buffer|
            global_allocator.destroy(buffer);
        global_buffers_trashcan.deinit();
    }

    const window_width: u32 = 800;
    const window_height: u32 = 600;

    var window = try glfw_window.init(window_width, window_height);
    defer glfw_window.deinit(&window);

    try renderer.init(&window, window_width, window_height);
    defer renderer.deinit();

    input_layer.inputLayerInit();
    defer input_layer.inputLayerDeinit();

    command_line.init();
    defer command_line.deinit();

    _ = try buffer_ops.createBuffer("build.zig");
    _ = try buffer_ops.createBuffer("src/buffer.zig");
    _ = try buffer_ops.createBuffer("src/buffer_operations.zig");
    _ = try buffer_ops.createBuffer("src/main.zig");
    focused_buffer = global_buffers.items[0];

    while (!window.shouldClose()) {
        try renderer.render(focused_buffer);
        try glfw.pollEvents();
    }
}
