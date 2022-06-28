const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");

const c = @import("c.zig");
const input = @import("input.zig");
const Cursor = @import("cursor.zig");
const Buffer = @import("buffer.zig");
const Renderer = @import("ui/renderer.zig");
const matrices = @import("matrices.zig");

// variables
var window_width: u32 = 800;
var window_height: u32 = 600;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

export var buffer: *Buffer = undefined;
export var start: i32 = 0;

var renderer: Renderer = undefined;

pub fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
    c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));
    window_width = width;
    window_height = height;

    var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);
    renderer.text.shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(renderer.text.shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    renderer.cursor.shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(renderer.cursor.shader.ID, "projection"), 1, c.GL_FALSE, &projection);
    _ = window;
}

pub fn cursorPositionCallback(window: glfw.Window, x_pos: f64, y_pos: f64) void {
    _ = window;
    _ = x_pos;
    _ = y_pos;
}

pub fn scrollCallback(window: glfw.Window, x_offset: f64, y_offset: f64) void {
    _ = window;
    _ = x_offset;
    start -= @floatToInt(i32, y_offset) * renderer.text.font_size;
    start = if (start <= 0)
        0
    else if (start >= buffer.lines.getLength() * @intCast(usize, renderer.text.font_size))
        @intCast(i32, (buffer.lines.getLength() - 1) * @intCast(usize, renderer.text.font_size))
    else
        start;
}

pub fn main() !void {
    defer _ = gpa.deinit();
    try glfw.init(.{});
    defer glfw.terminate();

    const window = try glfw.Window.create(window_width, window_height, "TestWindow", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_profile = glfw.Window.Hints.OpenGLProfile.opengl_core_profile,
    });
    defer window.destroy();
    try glfw.makeContextCurrent(window);

    _ = c.gladLoadGLLoader(@ptrCast(c.GLADloadproc, glfw.getProcAddress));
    c.glViewport(0, 0, @intCast(c_int, window_width), @intCast(c_int, window_height));

    renderer = try Renderer.init(window_width, window_height);

    window.setFramebufferSizeCallback(framebufferSizeCallback);
    window.setCharCallback(input.characterInputCallback);
    window.setKeyCallback(input.keyInputCallback);
    window.setCursorPosCallback(cursorPositionCallback);
    window.setScrollCallback(scrollCallback);

    // fonts
    buffer = try Buffer.init(gpa.allocator(), "build.zig");
    // buffer = try Buffer.init(allocator, "/home/ab55al/personal/prog/test/gap_buffer/file_10_000.txt");
    // buffer = try Buffer.init(allocator, "/home/ab55al/personal/prog/test/gap_buffer/file_100_000.txt");
    defer buffer.deinit();
    defer {
        buffer.lines.moveGapPosAbsolute(0);
        var i: usize = 0;
        while (i < buffer.lines.getLength()) : (i += 1) {
            buffer.lines.content[i + buffer.lines.getGapEndPos() + 1].printContent("{c}");
        }
    }

    // var ele = buffer.lines.elementAt(1);
    // var i: usize = 0;
    // while (i < ele.getLength()) : (i += 1) {
    //     print("{c}", .{ele.elementAt(i)});
    // }

    while (!window.shouldClose()) {
        c.glClearColor(0.2, 0.3, 0.3, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        try renderer.render(buffer, start);

        try window.swapBuffers();
        try glfw.pollEvents();
    }
}
