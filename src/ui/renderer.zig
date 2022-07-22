const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const unicode = std.unicode;
const glfw = @import("glfw");
const freetype = @import("freetype");
const harfbuzz = @import("harfbuzz");
const c_ft_hb = @import("c_ft_hb");

const c = @import("../c.zig");
const Shader = @import("shaders.zig");
const vectors = @import("vectors.zig");
const matrices = @import("matrices.zig");
const Rect = @import("rect.zig");
const text = @import("text.zig");
const Text = text.Text;
const Buffer = @import("../buffer.zig");
const GapBuffer = @import("../gap_buffer.zig").GapBuffer;
const utils = @import("../utils.zig");
const utf8 = @import("../utf8.zig");
const Window = @import("window.zig").Window;
const Windows = @import("window.zig").Windows;
const cursor = @import("cursor.zig");
const global_types = @import("../global_types.zig");
const Global = global_types.Global;
const GlobalInternal = global_types.GlobalInternal;

extern var global: Global;
extern var internal: GlobalInternal;

// Variables
var renderer_rect: Rect = undefined;
var renderer_text: *Text = undefined;
var window_width: u32 = 800;
var window_height: u32 = 600;
var start_of_y: i32 = 0;
var glfw_window: *glfw.Window = undefined;

pub fn init(window: *glfw.Window, width: u32, height: u32) !void {
    var text_shader = try Shader.init("shaders/text.vs", "shaders/text.fs");
    var rect_shader = try Shader.init("shaders/rect.vs", "shaders/rect.fs");

    glfw_window = window;
    var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);

    text_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(text_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    rect_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(rect_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    renderer_rect = Rect.init(rect_shader);
    renderer_text = try Text.init(text_shader);

    window_width = width;
    window_height = height;
}

pub fn deinit() void {
    renderer_text.deinit();
}

pub fn render() !void {
    c.glClearColor(0.2, 0.3, 0.3, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    var wins = internal.windows.wins.items;
    var i: usize = 0;
    while (i < wins.len) : (i += 1) {
        var window = internal.windows.wins.items[i];

        renderer_rect.renderFraction(window, .{ .x = 0.4, .y = 0.4, .z = 0.4 });
        try renderer_text.render(&window, .{ .x = 1.0, .y = 0.5, .z = 1.0 });
    }
    if (internal.windows.wins.items.len > 0)
        cursor.render(renderer_rect, renderer_text, internal.windows.focusedWindow().*, .{ .x = 0.0, .y = 0.0, .z = 0.0 });

    try glfw_window.swapBuffers();
}

pub fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
    window.setSize(.{ .width = width, .height = height }) catch |err| {
        print("Can't resize window err={}\n", .{err});
        return;
    };

    internal.os_window = .{ .width = @intToFloat(f32, width), .height = @intToFloat(f32, height) };
    c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));

    var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, width), @intToFloat(f32, height), 0, -1, 1);
    renderer_text.shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(renderer_text.shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    renderer_rect.shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(renderer_rect.shader.ID, "projection"), 1, c.GL_FALSE, &projection);
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
    _ = y_offset;
}
