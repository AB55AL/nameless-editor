const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const freetype = @import("freetype");

const c = @import("../c.zig");
const Shader = @import("shaders.zig");
const vectors = @import("../vectors.zig");
const matrices = @import("../matrices.zig");
const CursorRenderInfo = @import("cursor.zig");
const Text = @import("text.zig");
const Buffer = @import("../buffer.zig");
const GapBuffer = @import("../gap_buffer.zig").GapBuffer;
const utils = @import("../utils.zig");
const utf8 = @import("../utf8.zig");

pub const Renderer = @This();

cursor: CursorRenderInfo,
text: Text,
window_width: u32,
window_height: u32,

pub fn init(window_width: u32, window_height: u32) !Renderer {
    var text_shader = try Shader.init("shaders/font.vs", "shaders/font.fs");
    var cursor_shader = try Shader.init("shaders/cursor.vs", "shaders/cursor.fs");

    var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);

    text_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(text_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    cursor_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(cursor_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    var cursor = CursorRenderInfo.init(cursor_shader);

    const ft_lib = try freetype.Library.init();
    var face = try ft_lib.newFace("/usr/share/fonts/nerd-fonts-complete/TTF/mononoki-Regular Nerd Font Complete.ttf", 0);
    // var face = try ft_lib.newFace("/usr/share/fonts/TTF/Amiri-Regular.ttf", 0);
    // face = try ft_lib.newFace("/usr/share/fonts/nerd-fonts-complete/OTF/Fira Code Light Nerd Font Complete Mono.otf", 0);
    // defer ft_lib.deinit();
    // defer face.deinit();

    const font_size: i32 = 20;
    try face.setCharSize(64 * font_size, 0, 0, 0);

    var text = try Text.init(ft_lib, face, text_shader, font_size);

    return Renderer{
        .cursor = cursor,
        .text = text,
        .window_width = window_width,
        .window_height = window_height,
    };
}

// TODO: deinit()

pub fn render(renderer: Renderer, buffer: *Buffer, start: i32) !void {
    var cursor_x: i64 = 0;

    var i: u32 = 1;
    var l = buffer.lines.elementAt(buffer.cursor.row - 1).sliceOfContent();
    while (i < buffer.cursor.col) : (i += 1) {
        var slice = utf8.sliceOfUTF8Char(l, i);
        var code_point = try utf8.decode(slice);
        cursor_x += @intCast(i64, renderer.text.characters[code_point].Advance >> 6);
    }
    var cursor_h = renderer.text.font_size;
    var cursor_y = (@intCast(i32, buffer.cursor.row) - 1) * cursor_h + 10 - start;

    renderer.cursor.render(@intCast(i32, cursor_x), cursor_y, 1, cursor_h, .{ .x = 1.0, .y = 1.0, .z = 1.0 });

    var j: i32 = 0;
    // var lines = buffer.lines.sliceOfContent();
    var lines = try buffer.copyOfRows(1, @intCast(u32, buffer.lines.length()));
    defer buffer.allocator.free(lines);
    var iter = utils.splitAfter(u8, lines, '\n');
    while (iter.next()) |line| {
        renderer.text.render(line, 0, renderer.text.font_size - start + j, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
        j += renderer.text.font_size;
    }
}

// pub fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
//     c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));
//     window_width = width;
//     window_height = height;

//     var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);
//     text_shader.use();
//     c.glUniformMatrix4fv(c.glGetUniformLocation(text_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

//     cursor_shader.use();
//     c.glUniformMatrix4fv(c.glGetUniformLocation(cursor_shader.ID, "projection"), 1, c.GL_FALSE, &projection);
//     _ = window;
// }
