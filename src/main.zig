const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const c = @import("c.zig");
const Buffer = @import("buffer.zig");
const renderer = @import("ui/renderer.zig");
const file_io = @import("file_io.zig");
const command_line = @import("command_line.zig");
const glfw_window = @import("glfw.zig");

const input_layer = @import("input_layer");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
export var global_allocator = gpa.allocator();

export var buffer: *Buffer = undefined;

pub fn main() !void {
    defer _ = gpa.deinit();

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

    buffer = &(file_io.openFile(global_allocator, "build.zig") catch |err| {
        print("{}\n", .{err});
        return;
    });
    defer buffer.deinit();

    while (!window.shouldClose()) {
        try renderer.render(buffer);
        try glfw.pollEvents();
    }
}
