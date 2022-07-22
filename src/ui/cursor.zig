const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;

const utils = @import("../utils.zig");
const utf8 = @import("../utf8.zig");
const Window = @import("window.zig").Window;
const Rect = @import("rect.zig");
const vectors = @import("vectors.zig");
const text = @import("text.zig");
const Text = text.Text;
const Cursor = @import("../cursor.zig");
const Character = text.Character;
const Buffer = @import("../buffer.zig");
const WindowPixels = @import("window.zig").WindowPixels;

pub fn render(rect: Rect, renderer_text: *Text, window: Window, color: vectors.vec3) void {
    var cursor = window.buffer.cursor;
    var buffer = window.buffer;

    var window_p = WindowPixels.convert(window);

    var initial_cursor_h = renderer_text.font_size;
    var cursor_h = @intToFloat(f32, initial_cursor_h) / 2.0 + 5.0;
    var cursor_y =
        @intToFloat(f32, (@intCast(i32, cursor.row - 1) * initial_cursor_h) +
        @floatToInt(i32, window_p.y) + initial_cursor_h);
    var cursor_x = window_p.x;

    var i: u32 = 1;
    var line = utils.getLine(buffer.lines.sliceOfContent(), cursor.row);
    var it = text.splitByLanguage(line);
    while (it.next()) |text_segment| : (i += 1) {
        if (i >= cursor.col) break;

        if (text_segment.is_ascii) {
            var character = renderer_text.ascii_textures[text_segment.utf8_seq[0]];
            cursor_x += @intToFloat(f32, character.Advance >> 6);
        } else {
            var characters = renderer_text.unicode_textures.get(text_segment.utf8_seq) orelse continue;
            for (characters) |character| {
                cursor_x += @intToFloat(f32, character.Advance >> 6);
                i += 1;
                if (i >= cursor.col) break;
            }
        }
    }

    rect.render(cursor_x, cursor_y, 1, -cursor_h, color);
}
