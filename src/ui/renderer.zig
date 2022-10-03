const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const unicode = std.unicode;
const glfw = @import("glfw");
const freetype = @import("freetype");
const harfbuzz = @import("harfbuzz");
const c_ft_hb = @import("c_ft_hb");

const c = @import("c.zig");
const Shader = @import("shaders.zig");
const matrices = @import("matrices.zig");
const Rect = @import("rect.zig");
const text = @import("text.zig");
const Text = text.Text;
const utils = @import("../editor/utils.zig");
const utf8 = @import("../editor/utf8.zig");
const Window = @import("window.zig").Window;
const Windows = @import("window.zig").Windows;
const cursor = @import("cursor.zig");
const globals = @import("../globals.zig");
const VCursor = @import("vcursor.zig").VCursor;
const syntax = @import("syntax-highlight.zig");

const global = globals.global;
const internal = globals.internal;

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

    var wins = global.windows.wins.items;
    var i: usize = 0;
    while (i < wins.len) : (i += 1) {
        var window = &global.windows.wins.items[i];

        const bg_color = if (window.index == global.windows.focused_window_index)
            0x272822
        else
            window.background_color;

        renderer_rect.renderFraction(window.*, syntax.hexToColorVector(bg_color));
        if (window.buffer.index != null)
            try renderer_text.render(window);
    }
    if (global.command_line_is_open.*) {
        renderer_rect.renderFraction(internal.command_line_window, .{ .x = 0.0, .y = 0.0, .z = 0.0 });
        try renderer_text.render(&internal.command_line_window);
        cursor.render(renderer_rect, renderer_text, &internal.command_line_window, .{ .x = 1.0, .y = 0.0, .z = 0.0 });
    } else if (global.windows.wins.items.len > 0) {
        if (global.windows.focusedWindow().buffer.index != null) {
            cursor.render(renderer_rect, renderer_text, global.windows.focusedWindow(), .{ .x = 1.0, .y = 1.0, .z = 1.0 });
        }
    }

    try glfw_window.swapBuffers();
}

pub fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
    window.setSize(.{ .width = width, .height = height }) catch |err| {
        print("Can't resize window err={}\n", .{err});
        return;
    };

    internal.os_window.* = .{ .width = @intToFloat(f32, width), .height = @intToFloat(f32, height) };
    c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));

    var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, width), @intToFloat(f32, height), 0, -1, 1);
    renderer_text.shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(renderer_text.shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    renderer_rect.shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(renderer_rect.shader.ID, "projection"), 1, c.GL_FALSE, &projection);
    // _ = window;
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
