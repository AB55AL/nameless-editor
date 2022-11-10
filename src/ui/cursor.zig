const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;

const internal = @import("../globals.zig").internal;

const utils = @import("../editor/utils.zig");
const utf8 = @import("../editor/utf8.zig");
const Window = @import("window.zig").Window;
const Rect = @import("rect.zig");
const vectors = @import("vectors.zig");
const text = @import("text.zig");
const Text = text.Text;
const Character = text.Character;
const Buffer = @import("../editor/buffer.zig");
const WindowPixels = @import("window.zig").WindowPixels;
const VCursor = @import("vcursor.zig").VCursor;

pub fn render(rect: Rect, renderer_text: *Text, window: *Window, color: vectors.vec3) !void {
    var vcursor = VCursor.convert(window.buffer, window.*);
    var buffer = window.buffer;
    var initial_cursor_h = @intToFloat(f32, renderer_text.font_size);
    var cursor_h = initial_cursor_h / 2.0 + 5.0;

    var line = try buffer.getLine(internal.allocator, buffer.getRowAndCol(buffer.cursor_index).row);
    defer internal.allocator.free(line);
    var cursor_x = getX(renderer_text, window, &vcursor, line);
    var cursor_y = getY(window, &vcursor, initial_cursor_h);
    rect.render(cursor_x, cursor_y, 1, -cursor_h, color);

    // Vertical scroll
    if (vcursor.row > window.visible_rows)
        window.start_row += 1
    else if (vcursor.row == 0)
        window.start_row -= 1;
}

fn wrapOrStop(renderer_text: *Text, window: *Window, vcursor: *VCursor, x: *f32, y: *f32, character: Character) !void {
    var window_p = WindowPixels.convert(window.*);
    var advance = @intToFloat(f32, character.Advance >> 6);
    if (x.* >= window_p.width + window_p.x - advance) {
        if (vcursor.wrap_cursor) {
            y.* += @intToFloat(f32, renderer_text.font_size);
            x.* = window_p.x;
            vcursor.row += 1;
            if (y.* >= window_p.height + window_p.y) return error.CoordOutOfBounds;
        } else {
            return error.CoordOutOfBounds;
        }
    }
}

fn getY(window: *Window, vcursor: *VCursor, initial_cursor_h: f32) f32 {
    var window_p = WindowPixels.convert(window.*);
    // TODO: wrap cursor
    if (vcursor.wrap_cursor) {}

    var row = if (vcursor.row == 0) 1 else vcursor.row - 1;
    var y = (@intToFloat(f32, row) * initial_cursor_h) +
        window_p.y + initial_cursor_h;

    y = std.math.min(y, window_p.height + window_p.y);

    return y;
}

fn getX(renderer_text: *Text, window: *Window, vcursor: *VCursor, line: []const u8) f32 {
    var window_p = WindowPixels.convert(window.*);
    var x: f32 = window_p.x;
    var y: f32 = window_p.y;

    var col = std.math.max(1, vcursor.col);
    const e = std.math.min(col, line.len) - 1;
    if (e == 0) return x;
    var visible_line = utf8.substringOfUTF8Sequence(line, 1, e) catch unreachable;

    var i: u64 = 0;
    while (i < visible_line.len) {
        const byte = line[i];
        if (byte & 0b1_0000000 == 0) {
            var character = renderer_text.ascii_textures[byte];
            wrapOrStop(renderer_text, window, vcursor, &x, &y, character) catch break;
            x += @intToFloat(f32, character.Advance >> 6);
            i += 1;
        } else {
            const byte_len = unicode.utf8ByteSequenceLength(byte) catch unreachable;
            const bytes = visible_line[i .. i + byte_len];
            i += byte_len;
            var characters = renderer_text.unicode_textures.get(bytes) orelse continue;
            for (characters) |character| {
                wrapOrStop(renderer_text, window, vcursor, &x, &y, character) catch break;
                x += @intToFloat(f32, character.Advance >> 6);
            }
        }
    }

    return x;
}
