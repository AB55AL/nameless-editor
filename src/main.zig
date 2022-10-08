const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const Buffer = @import("editor/buffer.zig");
const renderer = @import("ui/renderer.zig");
const Window = @import("ui/window.zig").Window;
const command_line = @import("editor/command_line.zig");
const glfw_window = @import("ui/glfw.zig");
const buffer_ops = @import("editor/buffer_ops.zig");
const globals = @import("globals.zig");
const layouts = @import("ui/layouts.zig");

const input_layer = @import("input_layer");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    defer _ = gpa.deinit();

    const window_width: u32 = 800;
    const window_height: u32 = 600;

    try globals.initGlobals(gpa.allocator(), window_width, window_height);
    defer globals.deinitGlobals();

    var window = try glfw_window.init(window_width, window_height);
    defer glfw_window.deinit(&window);

    try renderer.init(&window, window_width, window_height);
    defer renderer.deinit();

    try input_layer.inputLayerInit();
    defer input_layer.inputLayerDeinit();

    try command_line.init();
    defer command_line.deinit();

    var tr = layouts.TileRight.init(1);
    try globals.global.layouts.add(tr.interface(), tr);
    globals.global.windows.active_layout = globals.global.layouts.layouts.items[0];

    try buffer_ops.openBufferFP("build.zig", .here);
    // try buffer_ops.openBufferFP("src/editor/buffer_ops.zig", .right);
    // try buffer_ops.openBufferFP("src/core.zig", .right);
    // try buffer_ops.openBufferFP("src/editor/buffer.zig", .above);
    // try buffer_ops.openBufferFP("src/editor/command_line.zig", .right);

    if (globals.global.first_buffer == null) {
        var buffer = try buffer_ops.createPathLessBuffer();
        try buffer_ops.openBufferI(buffer.index, .here);
    }

    while (!window.shouldClose()) {
        if (globals.global.valid_buffers_count == 0) window.setShouldClose(true);
        try renderer.render();
        try glfw.pollEvents();
    }
}
