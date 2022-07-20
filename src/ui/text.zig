const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const builtin = @import("builtin");
const StringArrayHashMap = std.StringArrayHashMap;

const freetype = @import("freetype");
const harfbuzz = @import("harfbuzz");
const c_ft_hb = @import("c_ft_hb");
const Shader = @import("shaders.zig").Shader;
const Face = freetype.Face;

const vectors = @import("../vectors.zig");
const c = @import("../c.zig");

extern var global_allocator: std.mem.Allocator;

pub const Character = struct {
    texture_id: u32, // ID handle of the glyph texture
    Size: vectors.uVector, // Size of glyph
    Bearing: vectors.iVector, // Offset from baseline to left/top of glyph
    Advance: u64, // Offset to advance to next glyph
};

pub const TextSegment = struct {
    utf8_seq: []const u8,
    is_ascii: bool,
};

pub fn splitByLanguage(utf8_seq: []const u8) splitByLanguageIterator() {
    return .{
        .buffer = utf8_seq,
        .start_index = 0,
        .end_index = 0,
    };
}

pub fn splitByLanguageIterator() type {
    return struct {
        buffer: []const u8,
        start_index: usize,
        end_index: usize,

        const Self = @This();

        /// Returns a slice of the next field, or null if splitting is complete.
        pub fn next(self: *Self) ?TextSegment {
            var i: usize = self.start_index;
            while (i < self.buffer.len) {
                const s = std.math.min(self.start_index, self.buffer.len);
                const e = std.math.min(self.end_index + 1, self.buffer.len);
                var byte = self.buffer[i];
                var next_byte = self.buffer[std.math.min(self.buffer.len - 1, i + 1)];

                if (isAsciiByte(byte)) {
                    self.end_index += 1;
                    self.start_index = self.end_index;
                    return TextSegment{ .utf8_seq = self.buffer[s..e], .is_ascii = Self.isAsciiString(self.buffer[s..e]) };
                } else if (isAsciiByte(next_byte) or i + 1 == self.buffer.len) {
                    self.end_index += 1;
                    self.start_index = self.end_index;
                    return TextSegment{ .utf8_seq = self.buffer[s..e], .is_ascii = Self.isAsciiString(self.buffer[s..e]) };
                } else {
                    self.end_index += 1;
                    i += 1;
                }
            }
            return null;
        }

        fn isAsciiString(utf8_seq: []const u8) bool {
            for (utf8_seq) |byte|
                if (byte & 0b1_0000000 != 0) return false;

            return true;
        }
        fn isAsciiByte(byte: u8) bool {
            if (byte & 0b1_0000000 == 0)
                return true
            else
                return false;
        }
    };
}

pub const Text = struct {
    font_size: i32,
    VAO: u32,
    VBO: u32,
    ascii_textures: [128]Character,
    unicode_textures: StringArrayHashMap([]const Character),
    ft_lib: freetype.Library,
    ft_face: Face,
    shader: Shader,
    hb_buffer: harfbuzz.Buffer,
    hb_font: harfbuzz.Font,

    /// Initializes data required for rendering text
    pub fn init(shader: Shader) !*Text {
        var text = try global_allocator.create(Text);
        text.ft_lib = try freetype.Library.init();
        text.ft_face = try text.ft_lib.newFace("/usr/share/fonts/TTF/Amiri-Regular.ttf", 0);
        // text.ft_face = try text.ft_lib.newFace("/usr/share/fonts/nerd-fonts-complete/OTF/Fira Code Light Nerd Font Complete Mono.otf", 0);

        const font_size: i32 = 18;
        try text.ft_face.setCharSize(64 * font_size, 0, 0, 0);
        shader.use();
        text.createVaoAndVbo();

        try text.generateAndCacheAsciiTextures();

        text.unicode_textures = StringArrayHashMap([]const Character).init(global_allocator);
        text.shader = shader;
        text.font_size = font_size;
        text.hb_font = harfbuzz.Font.fromFtFace(text.ft_face);
        text.hb_buffer = harfbuzz.Buffer.init().?;

        return text;
    }

    pub fn deinit(text: *Text) void {
        var iter = text.unicode_textures.iterator();
        while (iter.next()) |element| {
            global_allocator.free(element.value_ptr.*);
            global_allocator.free(element.key_ptr.*);
        }
        text.unicode_textures.deinit();

        text.hb_buffer.deinit();
        text.hb_font.deinit();
        text.ft_face.deinit();
        text.ft_lib.deinit();

        global_allocator.destroy(text);
    }

    pub fn generateAndCacheAsciiTextures(text: *Text) !void {
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1); // disable byte-alignment restriction

        var face = text.ft_face;

        var char: u8 = 0;
        while (char < text.ascii_textures.len) : (char += 1) {
            try face.loadChar(char, .{ .render = true });

            var texture: u32 = undefined;
            c.glGenTextures(1, &texture);
            c.glBindTexture(c.GL_TEXTURE_2D, texture);
            var bitmap = face.glyph().bitmap();

            if (bitmap.handle.buffer == null) {
                // std.debug.print("char is {c}  {}\n", .{ char, char });
                continue;
            }

            c.glTexImage2D(
                c.GL_TEXTURE_2D,
                0,
                c.GL_RED,
                @intCast(c_int, face.glyph().bitmap().width()),
                @intCast(c_int, face.glyph().bitmap().rows()),
                0,
                c.GL_RED,
                c.GL_UNSIGNED_BYTE,
                bitmap.buffer().?.ptr,
            );

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

            text.ascii_textures[char] = character;
        }

        // FIXME: Loading space in the above code produces incorrect values.
        {
            try face.loadChar(' ', .{ .render = true });
            var space_texture: u32 = undefined;
            c.glGenTextures(1, &space_texture);
            c.glBindTexture(c.GL_TEXTURE_2D, space_texture);

            var bitmap = face.glyph().bitmap();
            text.ascii_textures[32] = Character{
                .texture_id = space_texture,
                .Size = .{ .x = bitmap.width(), .y = bitmap.rows() },
                .Bearing = .{ .x = face.glyph().bitmapLeft(), .y = face.glyph().bitmapTop() },
                .Advance = @intCast(u64, face.glyph().advance().x),
            };
        }
    }

    pub fn generateAndCacheUnicodeTextures(text: *Text, utf8_seq: []const u8) ![]Character {
        text.hb_buffer.reset();

        text.hb_buffer.addUTF8(utf8_seq, 0, null);
        text.hb_buffer.guessSegmentProps();
        text.hb_font.shape(text.hb_buffer, &[_]harfbuzz.Feature{
            // harfbuzz.Feature.fromString("aalt[3:5]=2") orelse void,
        });

        // var infos = text.hb_buffer.getGlyphInfos();
        // var positions = text.hb_buffer.getGlyphPositions().?;

        var len: u32 = c_ft_hb.hb_buffer_get_length(text.hb_buffer.handle);
        var infos = c_ft_hb.hb_buffer_get_glyph_infos(text.hb_buffer.handle, null)[0..len];

        var characters_index: usize = 0;
        var characters = try global_allocator.alloc(
            Character,
            unicode.utf8CountCodepoints(utf8_seq) catch {
                print("unreachable here\n", .{});
                unreachable;
            },
        );

        text.shader.use();
        for (infos) |info| {
            text.ft_face.loadGlyph(info.codepoint, .{ .render = true }) catch |err| {
                print("err {}\n", .{err});
                print("{}\n\n", .{info});
                continue;
            };

            var glyph = text.ft_face.glyph();
            try glyph.render(freetype.RenderMode.normal);

            var glyph_buffer = glyph.bitmap().buffer() orelse continue;

            var width = glyph.bitmap().width();
            var rows = glyph.bitmap().rows();
            var bearing_x = glyph.bitmapLeft();
            var bearing_y = glyph.bitmapTop();

            var texture: u32 = undefined;
            c.glGenTextures(1, &texture);
            c.glBindTexture(c.GL_TEXTURE_2D, texture);

            c.glTexImage2D(
                c.GL_TEXTURE_2D,
                0,
                c.GL_RED,
                @intCast(c_int, width),
                @intCast(c_int, rows),
                0,
                c.GL_RED,
                c.GL_UNSIGNED_BYTE,
                &glyph_buffer[0],
            );

            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);

            const character = Character{
                .texture_id = texture,
                .Size = .{ .x = width, .y = rows },
                .Bearing = .{ .x = bearing_x, .y = bearing_y },
                .Advance = @intCast(u64, glyph.advance().x),
            };
            characters[characters_index] = character;
            characters_index += 1;
        }

        try text.unicode_textures.put(utf8_seq, characters);
        return characters;
    }

    pub fn render(text: *Text, string: []const u8, x_coord: i32, y_coord: i32, color: vectors.vec3) !void {
        var x = @intToFloat(f32, x_coord);
        var y = @intToFloat(f32, y_coord);

        var iter = splitByLanguage(string);
        while (iter.next()) |text_segment| {
            if (text_segment.is_ascii and text_segment.utf8_seq[0] == '\n' and builtin.mode != std.builtin.Mode.Debug) {
                continue;
            }

            c.glEnable(c.GL_CULL_FACE);
            c.glEnable(c.GL_BLEND);
            c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

            text.shader.use();
            c.glUniform3f(c.glGetUniformLocation(text.shader.ID, "textColor"), color.x, color.y, color.z);
            c.glActiveTexture(c.GL_TEXTURE0);
            c.glBindVertexArray(text.VAO);

            if (text_segment.is_ascii) {
                var character = text.ascii_textures[text_segment.utf8_seq[0]];
                text.renderGlyph(character, &x, &y);
            } else {
                var characters = text.unicode_textures.get(text_segment.utf8_seq) orelse blk: {
                    var utf8_seq = try global_allocator.alloc(u8, text_segment.utf8_seq.len);
                    std.mem.copy(u8, utf8_seq, text_segment.utf8_seq);
                    break :blk try text.generateAndCacheUnicodeTextures(utf8_seq);
                };
                for (characters) |character|
                    text.renderGlyph(character, &x, &y);
            }

            c.glBindVertexArray(0);
            c.glBindTexture(c.GL_TEXTURE_2D, 0);

            c.glDisable(c.GL_CULL_FACE);
            c.glDisable(c.GL_BLEND);
        }
    }

    pub fn renderGlyph(text: Text, character: Character, x_offset: *f32, y_offset: *f32) void {
        var xpos = x_offset.* + @intToFloat(f32, character.Bearing.x);
        var ypos = y_offset.* + @intToFloat(f32, @intCast(i64, character.Size.y) - character.Bearing.y);

        var w = @intToFloat(f32, character.Size.x);
        var h = @intToFloat(f32, character.Size.y);

        const vertices = [_]f32{
            xpos,     ypos - h, 0.0, 0.0,
            xpos,     ypos,     0.0, 1.0,
            xpos + w, ypos,     1.0, 1.0,
            xpos,     ypos - h, 0.0, 0.0,
            xpos + w, ypos,     1.0, 1.0,
            xpos + w, ypos - h, 1.0, 0.0,
        };

        c.glBindTexture(c.GL_TEXTURE_2D, character.texture_id);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, text.VBO);
        c.glBufferSubData(c.GL_ARRAY_BUFFER, 0, @sizeOf(f32) * vertices.len, &vertices);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 6);
        x_offset.* += @intToFloat(f32, (character.Advance >> 6)); // bitshift by 6 to get value in pixels (2^6 = 64)
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
};
