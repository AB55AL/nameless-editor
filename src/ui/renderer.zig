const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const freetype = @import("freetype");

const c = @import("../c.zig");
// const Shader = @import("shaders.zig").Shader;
const Shader = @import("shaders.zig");
const vectors = @import("../vectors.zig");
const matrices = @import("../matrices.zig");
const CursorRenderInfo = @import("cursor.zig");
// const Text = @import("text.zig").Text;
const Text = @import("text.zig");
const Buffer = @import("../buffer.zig");

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
    // face = try ft_lib.newFace("/usr/share/fonts/nerd-fonts-complete/OTF/Fira Code Light Nerd Font Complete Mono.otf", 0);
    // defer ft_lib.deinit();
    // defer face.deinit();

    const font_size: i32 = 48;
    try face.setCharSize(60 * font_size, 0, 0, 0);

    var text = try Text.init(ft_lib, face, text_shader, font_size);

    return Renderer{
        .cursor = cursor,
        .text = text,
        .window_width = window_width,
        .window_height = window_height,
    };
}

// TODO: deinit()

pub fn render(renderer: Renderer, buffer: *Buffer) !void {
    var array = ArrayList(u8).init(buffer.allocator);
    defer array.deinit();
    for (buffer.content.items) |gb| {
        var i: usize = 0;
        while (i < gb.content.len) : (i += 1) {
            if (i == gb.gap_pos) i += gb.gap_size;
            if (i >= gb.content.len) break;
            try array.append(gb.content[i]);
        }
    }

    var cursor_w = @intCast(i32, renderer.text.characters[0].Advance >> 6);
    var cursor_h = renderer.text.font_size;
    var cursor_y = (buffer.cursor.row - 1) * cursor_h + 10;
    var cursor_x = buffer.cursor.col * cursor_w - cursor_w;

    renderer.cursor.render(cursor_x, cursor_y, 1, cursor_h, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
    renderer.text.render(array.items, 0, renderer.text.font_size, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
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
