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
const buffer_ops = @import("editor/buffer_operations.zig");
const globals = @import("globals.zig");

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

    input_layer.inputLayerInit();
    defer input_layer.inputLayerDeinit();

    try command_line.init();
    defer command_line.deinit();

    try buffer_ops.openBuffer(null, "build.zig", .here);
    try buffer_ops.openBuffer(null, "src/editor/buffer_operations.zig", .right);
    try buffer_ops.openBuffer(null, "src/editor/buffer.zig", .above);
    try buffer_ops.openBuffer(null, "src/editor/command_line.zig", .right);

    if (globals.global.buffers.items.len == 0) {
        var buffer = try globals.internal.allocator.create(Buffer);
        buffer.* = try Buffer.init(globals.internal.allocator, "", "");
        try globals.global.buffers.append(buffer);
        try buffer_ops.openBuffer(1, null, .here);
    }

    while (!window.shouldClose()) {
        if (globals.global.buffers.items.len == 0) window.setShouldClose(true);
        try renderer.render();
        try glfw.pollEvents();
    }
}
