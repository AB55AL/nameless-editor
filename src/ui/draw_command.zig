const std = @import("std");
const print = std.debug.print;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

const c = @import("c.zig");
const math = @import("math.zig");
const shape2d = @import("shape2d.zig");
const ShapeCommand = shape2d.ShapeCommand;
const Glyph = @import("shape2d.zig").Glyph;
const Device = @import("device.zig");
const Vertex = Device.Vertex;

pub const Batch = struct {
    clip: shape2d.Rect,
    elements_count: u64,
    texture: u32,
    is_text: bool = false,
};

pub const DrawList = struct {
    vertices: ArrayList(Vertex),
    elements: ArrayList(u16),
    batches: ArrayList(Batch),
    max_element: u16 = 0,

    pub fn init(allocator: std.mem.Allocator) DrawList {
        return .{
            .vertices = ArrayList(Vertex).init(allocator),
            .elements = ArrayList(u16).init(allocator),
            .batches = ArrayList(Batch).init(allocator),
        };
    }

    pub fn deinit(draw_list: *DrawList) void {
        draw_list.vertices.deinit();
        draw_list.elements.deinit();
        draw_list.batches.deinit();
    }

    fn endTheBatch(draw_list: *DrawList, texture: u32, clip: ?shape2d.Rect) bool {
        if (draw_list.batches.items.len == 0) return true;

        var last_batch = draw_list.batches.items[draw_list.batches.items.len - 1];

        const same_texture = last_batch.texture == texture;
        const same_clip = if (clip) |clp| last_batch.clip.eql(clp) else true;

        return !same_texture or !same_clip;
    }

    pub fn pushText(draw_list: *DrawList, font: shape2d.Font, boundry: shape2d.Rect, const_x: f32, const_y: f32, color: u24, string: []const u8, clip: ?shape2d.Rect) !math.Vec2(f32) {
        var elements_count: u64 = 0;

        var x = const_x;
        var y = const_y;
        var space_to_next_line: f32 = 0;
        for (string) |char| {
            var g = font.glyphs.get(char) orelse continue;
            var gw = @intToFloat(f32, g.size.x);
            var gh = @intToFloat(f32, g.size.y);

            space_to_next_line = std.math.max(space_to_next_line, @intToFloat(f32, g.decent()) + font.yBaseLine());

            const glyph_offset_to_baseline = ((font.yBaseLine() - @intToFloat(f32, g.size.y)) + @intToFloat(f32, g.decent()));

            var vs = Vertex.createQuadUV(
                x,
                y + glyph_offset_to_baseline,
                gw,
                gh,
                g.uv_bottom_left,
                g.uv_top_right,
                color,
            );
            try draw_list.vertices.appendSlice(&vs);

            var elements = Vertex.quadIndices();
            elements_count += elements.len;
            var max_element = Device.offsetElementsBy(draw_list.max_element, &elements) + 1;
            draw_list.max_element = max_element;

            try draw_list.elements.appendSlice(&elements);

            x += @intToFloat(f32, g.advance);

            if (char == '\n') {
                x = boundry.x;
                y += font.newLineOffset();
            }
        }

        var last_batch_clip = if (draw_list.batches.items.len > 0) draw_list.batches.items[draw_list.batches.items.len - 1].clip else if (draw_list.batches.items.len != 0) draw_list.batches.items[0].clip else null;

        if (!draw_list.endTheBatch(font.atlas.texture_id, clip)) {
            var last_batch = &draw_list.batches.items[draw_list.batches.items.len - 1];
            last_batch.elements_count += elements_count;
        } else {
            try draw_list.batches.append(.{
                .clip = if (clip) |clp| clp else if (last_batch_clip) |lsc| lsc else .{ .x = const_x, .y = const_y, .w = 5000, .h = 5000 },
                .is_text = true,
                .texture = font.atlas.texture_id,
                .elements_count = elements_count,
            });
        }

        return .{ .x = x, .y = y };
    }

    pub fn pushRect(draw_list: *DrawList, x: f32, y: f32, w: f32, h: f32, color: u24, clip: ?shape2d.Rect) !void {
        try draw_list.vertices.appendSlice(&Vertex.createQuad(x, y, w, h, color));
        var elements = Vertex.quadIndices();
        var max_element = Device.offsetElementsBy(draw_list.max_element, &elements) + 1;
        try draw_list.elements.appendSlice(&elements);
        draw_list.max_element = max_element;

        if (!draw_list.endTheBatch(0, clip)) {
            var last_batch = &draw_list.batches.items[draw_list.batches.items.len - 1];
            last_batch.elements_count += elements.len;
        } else {
            var last_batch_clip = if (draw_list.batches.items.len > 0) draw_list.batches.items[draw_list.batches.items.len - 1].clip else if (draw_list.batches.items.len != 0) draw_list.batches.items[0].clip else null;
            try draw_list.batches.append(.{
                .clip = if (clip) |clp| clp else if (last_batch_clip) |lsc| lsc else .{ .x = x, .y = y, .w = w, .h = h },
                .is_text = false,
                .texture = 0,
                .elements_count = elements.len,
            });
        }
    }

    pub fn pushClip(draw_list: *DrawList, x: f32, y: f32, w: f32, h: f32) !void {
        var clip = shape2d.Rect{ .x = x, .y = y, .w = w, .h = h };

        if (draw_list.batches.items.len == 0) {
            try draw_list.batches.append(.{
                .clip = clip,
                .is_text = false,
                .texture = 0,
                .elements_count = 0,
            });
        } else {
            var last_batch = draw_list.batches.items[draw_list.batches.items.len - 1];
            if (!last_batch.clip.eql(clip)) {
                try draw_list.batches.append(.{
                    .clip = clip,
                    .is_text = false,
                    .texture = 0,
                    .elements_count = 0,
                });
            }
        }
    }
};
