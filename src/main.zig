const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const freetype = @import("freetype");
const c = @import("c.zig");

const GapBuffer = @import("GapBuffer.zig");
const shaders = @import("shaders.zig");
const matrices = @import("matrices.zig");
const text = @import("text.zig");
const input = @import("input.zig");
const Cursor = @import("cursor.zig");
const Buffer = @import("buffer.zig");

// variables
var window_width: u32 = 800;
var window_height: u32 = 600;

var text_shader: shaders.Shader = undefined;
export var cursor_shader: shaders.Shader = undefined;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
// export var allocator = gpa.allocator();
export var allocator = arena.allocator();

export var face: freetype.Face = undefined;
export var txt: text.Text = undefined;
export var font_size: i32 = 20;
export var cursor: Cursor = undefined;
export var buffer: *Buffer = undefined;

fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
    c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));
    window_width = width;
    window_height = height;

    var text_projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);
    text_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(text_shader.ID, "projection"), 1, c.GL_FALSE, &text_projection);

    var cursor_projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);
    cursor_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(cursor_shader.ID, "projection"), 1, c.GL_FALSE, &cursor_projection);
    _ = window;
}

pub fn main() !void {
    defer _ = gpa.deinit();
    defer arena.deinit();
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
    window.setFramebufferSizeCallback(framebufferSizeCallback);
    window.setCharCallback(input.characterInputCallback);
    window.setKeyCallback(input.keyInputCallback);

    // Paths should be relative to main.zig
    text_shader = try shaders.init("shaders/font.vs", "shaders/font.fs");

    cursor_shader = try shaders.init("shaders/cursor.vs", "shaders/cursor.fs");

    var text_projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);
    text_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(text_shader.ID, "projection"), 1, c.GL_FALSE, &text_projection);
    var cursor_projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);
    cursor_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(cursor_shader.ID, "projection"), 1, c.GL_FALSE, &cursor_projection);

    // fonts
    const ft_lib = try freetype.Library.init();
    defer ft_lib.deinit();
    face = try ft_lib.newFace("/usr/share/fonts/nerd-fonts-complete/TTF/mononoki-Regular Nerd Font Complete.ttf", 0);
    // face = try ft_lib.newFace("/usr/share/fonts/nerd-fonts-complete/OTF/Fira Code Light Nerd Font Complete Mono.otf", 0);
    defer face.deinit();

    try face.setCharSize(60 * font_size, 0, 0, 0);

    txt = try text.init(face, text_shader);

    buffer = try Buffer.init(allocator, "build.zig");
    // buffer = try Buffer.init(allocator, "/home/ab55al/personal/prog/test/gap_buffer/file_10_000.txt");
    // buffer = try Buffer.init(allocator, "/home/ab55al/personal/prog/test/gap_buffer/file_100_000.txt");
    defer buffer.deinit();

    // depth is 11
    // var i: u32 = 0;
    // while (i < 10) : (i += 1) {
    // var j: i32 = 1;
    // }
    // try buffer.delete(1, 1, 2);
    // buffer.content.items[0] = (try Rope.delete(&buffer.content.items[0], allocator, 1, 6)).*;
    // buffer.content.items[0].traverse(true);

    var gbuffer = &buffer.content.items[0];
    gbuffer.moveGapPosAbsolute(0);
    while (!window.shouldClose()) {
        var array = ArrayList(u8).init(allocator);
        defer array.deinit();
        for (buffer.content.items) |gb| {
            var i: usize = 0;
            while (i < gb.content.len) : (i += 1) {
                if (i == gb.gap_pos) i += gb.gap_size;
                if (i >= gb.content.len) break;
                try array.append(gb.content[i]);
            }
        }
        // buf = array.items;
        cursor = buffer.cursor;
        c.glClearColor(0.2, 0.3, 0.3, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        var char = buffer.charAt(cursor.row, cursor.col) orelse 'a';
        // print("{c}\n", .{char});
        var cursor_w = @intCast(i32, txt.characters[char].Advance >> 6);
        var cursor_h = font_size;
        var cursor_y = (cursor.row - 1) * cursor_h + 10;
        var cursor_x = cursor.col * cursor_w - cursor_w;

        cursor.render(cursor_shader, cursor_x, cursor_y, 1, cursor_h, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
        txt.render(text_shader, array.items, 0, font_size, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
        // txt.render(text_shader, array.items[0..100], 0, font_size, .{ .x = 1.0, .y = 1.0, .z = 1.0 });

        try window.swapBuffers();
        try glfw.pollEvents();
    }
}
