const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const Buffer = @import("editor/buffer.zig");
const renderer = @import("ui/renderer.zig");
const Window = @import("ui/window.zig").Window;
const Windows = @import("ui/window.zig").Windows;
const OSWindow = @import("ui/window.zig").OSWindow;
const command_line = @import("editor/command_line.zig");
const glfw_window = @import("ui/glfw.zig");
const buffer_ops = @import("editor/buffer_ops.zig");
const Layouts = @import("ui/layouts.zig").Layouts;
const TileRight = @import("ui/layouts.zig").TileRight;

const input_layer = @import("input_layer");

const globals = @import("globals.zig");
const global = globals.global;
const internal = globals.internal;

pub export fn editorEntry(
    // internal
    allocator: *std.mem.Allocator,
    buffers_trashcan: *ArrayList(*Buffer),
    command_line_window: *Window,
    os_window: *OSWindow,
    // global
    focused_buffer: *Buffer,
    buffers: *ArrayList(*Buffer),
    command_line_buffer: *Buffer,
    command_line_is_open: *bool,
    layouts: *Layouts,
    windows: *Windows,
    // window system stuff
    window: *glfw.Window,
    window_width: u32,
    window_height: u32,
) void {
    internal.allocator = allocator.*;
    internal.buffers_trashcan = buffers_trashcan;
    internal.command_line_window = command_line_window.*;
    internal.os_window = os_window;

    global.focused_buffer = focused_buffer;
    global.buffers = buffers;
    global.command_line_buffer = command_line_buffer;
    global.command_line_is_open = command_line_is_open;
    global.layouts = layouts;
    global.windows = windows;

    run(window, window_width, window_height) catch unreachable;
}

fn run(
    window: *glfw.Window,
    window_width: u32,
    window_height: u32,
) !void {
    try renderer.init(window, window_width, window_height);
    defer renderer.deinit();

    input_layer.inputLayerInit();
    defer input_layer.inputLayerDeinit();

    try command_line.init();
    defer command_line.deinit();

    var tr = TileRight.init(1);
    try globals.global.layouts.add(tr.interface(), tr);
    globals.global.windows.active_layout = globals.global.layouts.layouts.items[0];

    // FIXME: opening with Direction.here causes unreachable code to be reached
    // try buffer_ops.openBuffer(null, "build.zig", .here);
    try buffer_ops.openBuffer(null, "src/editor/buffer_ops.zig", .right);
    try buffer_ops.openBuffer(null, "src/core.zig", .right);
    try buffer_ops.openBuffer(null, "src/editor/buffer.zig", .above);
    try buffer_ops.openBuffer(null, "src/editor/command_line.zig", .right);

    if (globals.global.buffers.items.len == 0) {
        var buffer = try globals.internal.allocator.create(Buffer);
        buffer.* = try Buffer.init(globals.internal.allocator, "", "");
        try globals.global.buffers.append(buffer);
        try buffer_ops.openBuffer(1, null, .here);
    }

    var i: usize = 0;
    while (!window.shouldClose()) {
        if (globals.global.buffers.items.len == 0) window.setShouldClose(true);

        const t = std.time.milliTimestamp();
        try renderer.render();
        print("{}\n", .{std.time.milliTimestamp() - t});
        i += 1;
        if (i == 100)
            globals.global.command_line_is_open.* = false;

        try glfw.pollEvents();
    }
}
