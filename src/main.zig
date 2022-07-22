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
const global_types = @import("global_types.zig");
const Global = global_types.Global;
const GlobalInternal = global_types.GlobalInternal;

const input_layer = @import("input_layer");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

export var global = Global{
    .focused_buffer = undefined,
    .buffers = undefined,
};

export var internal = GlobalInternal{
    .allocator = undefined,
    .buffers_trashcan = undefined,
};

pub fn main() !void {
    defer _ = gpa.deinit();

    internal.allocator = gpa.allocator();
    internal.buffers_trashcan = ArrayList(*Buffer).init(internal.allocator);

    global.buffers = ArrayList(*Buffer).init(internal.allocator);

    defer {
        for (global.buffers.items) |buffer|
            buffer.deinitAndDestroy();
        global.buffers.deinit();

        for (internal.buffers_trashcan.items) |buffer|
            internal.allocator.destroy(buffer);
        internal.buffers_trashcan.deinit();
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
    global.focused_buffer = global.buffers.items[0];

    while (!window.shouldClose()) {
        try renderer.render(global.focused_buffer);
        try glfw.pollEvents();
    }
}
