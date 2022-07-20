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
const vectors = @import("../vectors.zig");
const matrices = @import("../matrices.zig");
const CursorRenderInfo = @import("cursor.zig");
const text = @import("text.zig");
const Text = text.Text;
const Buffer = @import("../buffer.zig");
const GapBuffer = @import("../gap_buffer.zig").GapBuffer;
const utils = @import("../utils.zig");
const utf8 = @import("../utf8.zig");

pub const Renderer = @This();

cursor: CursorRenderInfo,
text: *Text,
window_width: u32,
window_height: u32,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, window_width: u32, window_height: u32) !Renderer {
    var text_shader = try Shader.init("shaders/font.vs", "shaders/font.fs");
    var cursor_shader = try Shader.init("shaders/cursor.vs", "shaders/cursor.fs");

    var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);

    text_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(text_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    cursor_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(cursor_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    var cursor = CursorRenderInfo.init(cursor_shader);

    var txt = try Text.init(allocator, text_shader);

    return Renderer{
        .cursor = cursor,
        .text = txt,
        .window_width = window_width,
        .window_height = window_height,
        .allocator = allocator,
    };
}

pub fn deinit(renderer: Renderer) void {
    renderer.text.deinit();
}

pub fn render(renderer: Renderer, buffer: *Buffer, start: i32) !void {
    var j: i32 = 0;
    var lines = try buffer.lines.copy();
    defer buffer.allocator.free(lines);
    var iter = utils.splitAfter(u8, lines, '\n');
    while (iter.next()) |line| {
        try renderer.text.render(line, 0, renderer.text.font_size - start + j, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
        j += renderer.text.font_size;
    }

    var cursor_x: i64 = 0;

    var i: u32 = 1;
    var l = utils.getLine(buffer.lines.sliceOfContent(), buffer.cursor.row);
    var it = text.splitByLanguage(l);
    while (it.next()) |text_segment| : (i += 1) {
        if (i >= buffer.cursor.col) break;

        if (text_segment.is_ascii) {
            var character = renderer.text.ascii_textures[text_segment.utf8_seq[0]];
            cursor_x += @intCast(i64, character.Advance >> 6);
        } else {
            var characters = renderer.text.unicode_textures.get(text_segment.utf8_seq) orelse continue;
            for (characters) |character| {
                cursor_x += @intCast(i64, character.Advance >> 6);
                i += 1;
                if (i >= buffer.cursor.col) break;
            }
        }
    }
    var cursor_h = renderer.text.font_size;
    var cursor_y = (@intCast(i32, buffer.cursor.row) - 1) * cursor_h + 10 - start;

    renderer.cursor.render(@intCast(i32, cursor_x), cursor_y, 1, cursor_h, .{ .x = 1.0, .y = 1.0, .z = 1.0 });
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
