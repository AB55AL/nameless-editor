const std = @import("std");
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

const editor = @import("../globals.zig").editor;
const ui = @import("../globals.zig").ui;

const ft = @import("freetype");
const c = @import("c.zig");

const math = @import("math.zig");

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn eql(rect_1: Rect, rect_2: Rect) bool {
        return (rect_1.x == rect_2.x and
            rect_1.y == rect_2.y and
            rect_1.w == rect_2.w and
            rect_1.h == rect_2.h);
    }

    pub fn bottom(rect: Rect) f32 {
        return rect.y + rect.h;
    }

    pub fn right(rect: Rect) f32 {
        return rect.x + rect.w;
    }

    pub fn print(rect: Rect) void {
        std.debug.print("{d} {d} {d} {d}\n", .{ rect.x, rect.y, rect.w, rect.h });
    }
};

pub const Atlas = struct {
    texture_id: u32,
    width: u32,
    height: u32,

    row_baseline: u32,
    tallest_glpyh_in_row: u32,
    row_extent: u32,

    pub fn insert(atlas: *Atlas, glyph_data: []const u8, glyph_width: u32, glyph_rows: u32, bitmap_left: i32, bitmap_top: i32, x_advance: u64) !Glyph {
        c.glBindTexture(c.GL_TEXTURE_2D, atlas.texture_id);

        if (atlas.row_extent + glyph_width > atlas.width) atlas.advanceToNextRow();

        if (atlas.row_baseline + glyph_rows > atlas.height) {
            @panic("There's no space here!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        }

        c.glTexSubImage2D(
            c.GL_TEXTURE_2D,
            0,
            @intCast(c_int, atlas.row_extent), // x offset
            @intCast(c_int, atlas.row_baseline), // y offset
            @intCast(c_int, glyph_width),
            @intCast(c_int, glyph_rows),
            c.GL_RED,
            c.GL_UNSIGNED_BYTE,
            glyph_data.ptr,
        );

        var glyph = Glyph{
            .size = .{ .x = glyph_width, .y = glyph_rows },
            .bearing = .{ .x = bitmap_left, .y = bitmap_top },
            .advance = @intCast(u32, x_advance / 64),
            .uv_bottom_left = undefined,
            .uv_top_right = undefined,
        };
        const uv_coords = glyph.uvCoordsInAtlas(atlas.row_extent, atlas.row_baseline, atlas.width, atlas.height);
        glyph.uv_bottom_left = uv_coords.bottom_left_uv;
        glyph.uv_top_right = uv_coords.top_right_uv;

        atlas.row_extent += glyph_width;
        atlas.tallest_glpyh_in_row = std.math.max(atlas.tallest_glpyh_in_row, glyph_rows);

        c.glBindTexture(c.GL_TEXTURE_2D, 0);
        return glyph;
    }

    fn advanceToNextRow(atlas: *Atlas) void {
        atlas.row_baseline += atlas.tallest_glpyh_in_row;
        atlas.tallest_glpyh_in_row = 0;
        atlas.row_extent = 0;
    }
};

pub const Glyph = struct {
    size: math.Vec2(u32),
    bearing: math.Vec2(i32),
    uv_bottom_left: math.Vec2(f32),
    uv_top_right: math.Vec2(f32),

    advance: u32,

    pub fn decent(glyph: Glyph) i32 {
        return @intCast(i32, glyph.size.y) - glyph.bearing.y;
    }

    pub fn uOffset(x_offset_in_atlas: u32, atlas_width: u32) f32 {
        return @intToFloat(f32, x_offset_in_atlas) / @intToFloat(f32, atlas_width);
    }

    pub fn vOffset(y_offset_in_atlas: u32, atlas_height: u32) f32 {
        return @intToFloat(f32, y_offset_in_atlas) / @intToFloat(f32, atlas_height);
    }

    pub fn uvCoordsInAtlas(glyph: Glyph, x_offset_in_atlas: u32, y_offset_in_atlas: u32, atlas_width: u32, atlas_height: u32) struct {
        bottom_left_uv: math.Vec2(f32),
        top_right_uv: math.Vec2(f32),
    } {
        const bl = math.Vec2(f32){
            .x = uOffset(x_offset_in_atlas, atlas_width),
            .y = vOffset(y_offset_in_atlas + glyph.size.y, atlas_height),
        };
        const tr = math.Vec2(f32){
            .x = uOffset(x_offset_in_atlas + glyph.size.x, atlas_width),
            .y = vOffset(y_offset_in_atlas, atlas_height),
        };

        return .{ .bottom_left_uv = bl, .top_right_uv = tr };
    }
};

pub const Font = struct {
    atlas: Atlas,
    ft_lib: ft.Library,
    ft_face: ft.Face,
    glyphs: AutoHashMap(u8, Glyph),
    y_min: i32,
    y_max: i32,
    descender: i16,
    ascender: i16,
    max_advance_width: i16,
    max_advance_height: i16,

    pub fn init(allocator: std.mem.Allocator, font_name: []const u8, font_size: i32) !Font {
        var ft_lib = try ft.Library.init();
        var ft_face = try ft_lib.createFace(font_name, 0);
        try ft_face.setCharSize(64 * font_size, 0, 0, 0);

        var bbox = ft_face.bbox();

        var font = Font{
            .ft_lib = ft_lib,
            .ft_face = ft_face,
            .atlas = undefined,
            .glyphs = AutoHashMap(u8, Glyph).init(allocator),
            .max_advance_width = ft_face.maxAdvanceWidth() >> 6,
            .max_advance_height = ft_face.maxAdvanceHeight() >> 6,
            .y_min = @intCast(i32, bbox.yMin >> 6),
            .y_max = @intCast(i32, bbox.yMax >> 6),
            .descender = ft_face.descender() >> 6,
            .ascender = ft_face.ascender() >> 6,
        };

        { // atlas initialization
            font.atlas = Atlas{
                .texture_id = 0,
                .width = 1000,
                .height = 1000,
                .row_baseline = 0,
                .tallest_glpyh_in_row = 0,
                .row_extent = 0,
            };

            c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);

            c.glGenTextures(1, &font.atlas.texture_id);
            c.glBindTexture(c.GL_TEXTURE_2D, font.atlas.texture_id);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);

            c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RED, @intCast(c_int, font.atlas.width), @intCast(c_int, font.atlas.height), 0, c.GL_RED, c.GL_UNSIGNED_BYTE, null);

            var i: u8 = 0;
            while (i < 128) : (i += 1) {
                try font.ft_face.loadChar(i, .{ .render = true });
                var bitmap = font.ft_face.glyph().bitmap();
                var g = font.ft_face.glyph();
                if (g.bitmap().buffer() == null) continue;

                const glyph = try font.atlas.insert(
                    bitmap.buffer().?,
                    bitmap.width(),
                    bitmap.rows(),
                    g.bitmapLeft(),
                    g.bitmapTop(),
                    @intCast(u64, g.advance().x),
                );

                try font.glyphs.put(i, glyph);
            }

            {
                try font.ft_face.loadChar(' ', .{ .render = true });
                var g = font.ft_face.glyph();
                const glyph: Glyph = .{
                    .uv_bottom_left = .{ .x = 0, .y = 0 },
                    .uv_top_right = .{ .x = 0, .y = 0 },
                    .size = .{ .x = 0, .y = 0 },
                    .bearing = .{ .x = 0, .y = 0 },
                    .advance = @intCast(u32, g.advance().x >> 6),
                };
                try font.glyphs.put(' ', glyph);
            }
        }

        return font;
    }

    pub fn deinit(font: *Font) void {
        font.ft_face.deinit();
        font.ft_lib.deinit();
        font.glyphs.deinit();
    }

    pub fn newLineOffset(font: Font) f32 {
        return @intToFloat(f32, font.max_advance_height) + 1;
    }

    pub fn yBaseLine(font: Font) f32 {
        return @intToFloat(f32, 1 + (font.y_max + font.descender));
    }
};
