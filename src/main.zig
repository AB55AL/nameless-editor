const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const c = @import("c.zig");
const Buffer = @import("buffer.zig");
const renderer = @import("ui/renderer.zig");
const Window = @import("ui/window.zig").Window;
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
    .command_line_buffer = undefined,
};

export var internal = GlobalInternal{
    .allocator = undefined,
    .buffers_trashcan = undefined,
    .windows = undefined,
    .os_window = undefined,
    .command_line_window = undefined,
};

pub fn main() !void {
    defer _ = gpa.deinit();

    const window_width: u32 = 800;
    const window_height: u32 = 600;

    internal.allocator = gpa.allocator();

    global.command_line_buffer = try internal.allocator.create(Buffer);
    global.command_line_buffer.* = try Buffer.init("", "");

    internal.buffers_trashcan = ArrayList(*Buffer).init(internal.allocator);
    internal.windows.wins = ArrayList(Window).init(internal.allocator);
    internal.os_window = .{ .width = window_width, .height = window_height };
    internal.command_line_window = .{
        .x = 0,
        .y = 0.95,
        .width = 1,
        .height = 0.1,
        .buffer = global.command_line_buffer,
    };

    global.buffers = ArrayList(*Buffer).init(internal.allocator);

    defer {
        for (global.buffers.items) |buffer|
            buffer.deinitAndDestroy();
        global.buffers.deinit();

        for (internal.buffers_trashcan.items) |buffer|
            internal.allocator.destroy(buffer);
        internal.buffers_trashcan.deinit();

        internal.windows.wins.deinit();
        global.command_line_buffer.deinitAndDestroy();
    }

    var window = try glfw_window.init(window_width, window_height);
    defer glfw_window.deinit(&window);

    try renderer.init(&window, window_width, window_height);
    defer renderer.deinit();

    input_layer.inputLayerInit();
    defer input_layer.inputLayerDeinit();

    try command_line.init();
    defer command_line.deinit();

    if (global.buffers.items.len == 0) {
        var buffer = try internal.allocator.create(Buffer);
        buffer.* = try Buffer.init("", "");
        try global.buffers.append(buffer);
        try buffer_ops.openBuffer(1, null);
    }

    while (!window.shouldClose()) {
        if (global.buffers.items.len == 0) window.setShouldClose(true);
        try renderer.render();
        try glfw.pollEvents();
    }
}
