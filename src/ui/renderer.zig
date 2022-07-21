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

// Variables
extern var global_allocator: std.mem.Allocator;
extern var buffer: *Buffer;

var renderer_cursor: Rect = undefined;
var renderer_text: *Text = undefined;
var window_width: u32 = 800;
var window_height: u32 = 600;
var start_of_y: i32 = 0;
var glfw_window: *glfw.Window = undefined;

pub fn init(window: *glfw.Window, width: u32, height: u32) !void {
    var text_shader = try Shader.init("shaders/text.vs", "shaders/text.fs");
    var cursor_shader = try Shader.init("shaders/rect.vs", "shaders/rect.fs");

    glfw_window = window;
    var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, window_width), @intToFloat(f32, window_height), 0, -1, 1);

    text_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(text_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    cursor_shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(cursor_shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    renderer_cursor = Rect.init(cursor_shader);
    renderer_text = try Text.init(text_shader);

    window_width = width;
    window_height = height;
}

pub fn deinit() void {
    renderer_text.deinit();
}

pub fn render(buffer_to_render: *Buffer) !void {
    c.glClearColor(0.2, 0.3, 0.3, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    const window = Window{ .x = 100, .y = 100, .width = 250, .height = 500 };

    renderer_cursor.render(window.x, window.y, window.width, window.height, .{ .x = 0.4, .y = 0.4, .z = 0.4 });
    var lines = try buffer_to_render.lines.copy();
    defer global_allocator.free(lines);
    try renderer_text.render(window, lines, .{ .x = 1.0, .y = 0.5, .z = 1.0 });

    var cursor_x: i64 = 0;

    var i: u32 = 1;
    var l = utils.getLine(buffer.lines.sliceOfContent(), buffer.cursor.row);
    var it = text.splitByLanguage(l);
    while (it.next()) |text_segment| : (i += 1) {
        if (i >= buffer.cursor.col) break;

        if (text_segment.is_ascii) {
            var character = renderer_text.ascii_textures[text_segment.utf8_seq[0]];
            cursor_x += @intCast(i64, character.Advance >> 6);
        } else {
            var characters = renderer_text.unicode_textures.get(text_segment.utf8_seq) orelse continue;
            for (characters) |character| {
                cursor_x += @intCast(i64, character.Advance >> 6);
                i += 1;
                if (i >= buffer.cursor.col) break;
            }
        }
    }
    var cursor_h = renderer_text.font_size;
    var cursor_y = (@intCast(i32, buffer.cursor.row) - 1) * cursor_h + 10 - start_of_y;

    renderer_cursor.render(@intCast(i32, cursor_x), cursor_y, 1, cursor_h, .{ .x = 1.0, .y = 1.0, .z = 1.0 });

    try glfw_window.swapBuffers();
}

pub fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
    window.setSize(.{ .width = width, .height = height }) catch |err| {
        print("Can't resize window err={}\n", .{err});
        return;
    };
    c.glViewport(0, 0, @intCast(c_int, width), @intCast(c_int, height));

    var projection = matrices.createOrthoMatrix(0, @intToFloat(f32, width), @intToFloat(f32, height), 0, -1, 1);
    renderer_text.shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(renderer_text.shader.ID, "projection"), 1, c.GL_FALSE, &projection);

    renderer_cursor.shader.use();
    c.glUniformMatrix4fv(c.glGetUniformLocation(renderer_cursor.shader.ID, "projection"), 1, c.GL_FALSE, &projection);
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
    start_of_y -= @floatToInt(i32, y_offset) * renderer_text.font_size;
    start_of_y = if (start_of_y <= 0)
        0
    else if (start_of_y >= buffer.lines.length() * @intCast(usize, renderer_text.font_size))
        @intCast(i32, (buffer.lines.length() - 1) * @intCast(usize, renderer_text.font_size))
    else
        start_of_y;
}
