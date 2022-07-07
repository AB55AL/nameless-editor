const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const builtin = @import("builtin");

const freetype = @import("freetype");
const Shader = @import("shaders.zig").Shader;
const Face = freetype.Face;

const vectors = @import("../vectors.zig");
const c = @import("../c.zig");

pub const Text = @This();

pub const Character = struct {
    texture_id: u32, // ID handle of the glyph texture
    Size: vectors.uVector, // Size of glyph
    Bearing: vectors.iVector, // Offset from baseline to left/top of glyph
    Advance: u64, // Offset to advance to next glyph
};

font_size: i32,
VAO: u32,
VBO: u32,
characters: [0x700]Character,
ft_lib: freetype.Library,
face: Face,
shader: Shader,

/// Initializes data required for rendering text
pub fn init(ft_lib: freetype.Library, face: Face, shader: Shader, font_size: i32) !Text {
    var text: Text = undefined;

    shader.use();
    text.createVaoAndVbo();
    try text.generateAndCacheFontTextures(face);
    text.ft_lib = ft_lib;
    text.face = face;
    text.shader = shader;
    text.font_size = font_size;

    return text;
}

pub fn generateAndCacheFontTextures(text: *Text, face: Face) !void {
    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1); // disable byte-alignment restriction

    // FIXME: loading space char gives a null bitmap.handle.buffer
    {
        try face.loadChar(' ', .{ .render = true });
        var space_texture: u32 = undefined;
        c.glGenTextures(1, &space_texture);
        c.glBindTexture(c.GL_TEXTURE_2D, space_texture);

        var bitmap = face.glyph().bitmap();
        text.characters[32] = Character{
            .texture_id = space_texture,
            .Size = .{ .x = bitmap.width(), .y = bitmap.rows() },
            .Bearing = .{ .x = face.glyph().bitmapLeft(), .y = face.glyph().bitmapTop() },
            .Advance = @intCast(u64, face.glyph().advance().x),
        };
    }

    var char: u32 = 0;
    while (char < text.characters.len) : (char += 1) {
        try face.loadChar(char, .{ .render = true });

        var texture: u32 = undefined;
        c.glGenTextures(1, &texture);
        c.glBindTexture(c.GL_TEXTURE_2D, texture);
        var bitmap = face.glyph().bitmap();

        if (bitmap.handle.buffer == null) {
            // std.debug.print("char is {c}  {}\n", .{ char, char });
            continue;
        }

        // zig fmt: off
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RED,
            @intCast(c_int, face.glyph().bitmap().width()),
            @intCast(c_int, face.glyph().bitmap().rows()),
            0,
            c.GL_RED,
            c.GL_UNSIGNED_BYTE,
            bitmap.buffer().?.ptr);
        // zig fmt: on

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);

        const character = Character{
            .texture_id = texture,
            .Size = .{ .x = bitmap.width(), .y = bitmap.rows() },
            .Bearing = .{ .x = face.glyph().bitmapLeft(), .y = face.glyph().bitmapTop() },
            .Advance = @intCast(u64, face.glyph().advance().x),
        };

        text.characters[char] = character;
    }
}

pub fn render(text: Text, string: []const u8, x_coord: i32, y_coord: i32, color: vectors.vec3) !void {
    var x = x_coord;
    var y = y_coord;

    c.glEnable(c.GL_CULL_FACE);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

    text.shader.use();
    c.glUniform3f(c.glGetUniformLocation(text.shader.ID, "textColor"), color.x, color.y, color.z);
    c.glActiveTexture(c.GL_TEXTURE0);
    c.glBindVertexArray(text.VAO);

    var code_points = (try unicode.Utf8View.init(string)).iterator();
    while (code_points.nextCodepoint()) |code_point| {
        if (code_point == '\n' and builtin.mode != std.builtin.Mode.Debug) {
            continue;
        }
        const character = text.characters[code_point];

        var xpos = @intToFloat(f32, @intCast(i32, x) + character.Bearing.x);
        var ypos = @intToFloat(f32, y + (@intCast(i32, character.Size.y) - character.Bearing.y));

        var w = @intToFloat(f32, character.Size.x);
        var h = @intToFloat(f32, character.Size.y);

        // zig fmt: off
        const vertices = [_]f32{
            xpos    , ypos - h, 0.0, 0.0,
            xpos    , ypos    , 0.0, 1.0,
            xpos + w, ypos    , 1.0, 1.0,
            xpos    , ypos - h, 0.0, 0.0,
            xpos + w, ypos    , 1.0, 1.0,
            xpos + w, ypos - h, 1.0, 0.0,
        };
        // zig fmt: on

        c.glBindTexture(c.GL_TEXTURE_2D, character.texture_id);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, text.VBO);
        c.glBufferSubData(c.GL_ARRAY_BUFFER, 0, @sizeOf(f32) * vertices.len, &vertices);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 6);

        x += @intCast(i32, (character.Advance >> 6)); // bitshift by 6 to get value in pixels (2^6 = 64)
    }

    c.glBindVertexArray(0);
    c.glBindTexture(c.GL_TEXTURE_2D, 0);

    c.glDisable(c.GL_CULL_FACE);
    c.glDisable(c.GL_BLEND);
}

pub fn createVaoAndVbo(text: *Text) void {
    var VAO: u32 = undefined;
    c.glGenVertexArrays(1, &VAO);
    c.glBindVertexArray(VAO);

    var VBO: u32 = undefined;
    c.glGenBuffers(1, &VBO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);

    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32) * 6 * 4, null, c.GL_DYNAMIC_DRAW);
    c.glVertexAttribPointer(0, 4, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(0);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    text.VAO = VAO;
    text.VBO = VBO;
}
