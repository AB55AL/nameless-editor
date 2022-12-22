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

pub const Batches = struct {
    pub const Batch = struct {
        clip: shape2d.Rect,
        vertices_end_index: u64,
        elements_end_index: u64,
        texture: u32,
        is_text: bool = false,
    };

    vertices: []Vertex,
    elements: []u16,
    batches: []Batch,

    pub fn shapeCommandToBatches(arena_allocator: std.mem.Allocator, screen_width: f32, screen_height: f32, shape_cmds: ArrayList(ShapeCommand), font: shape2d.Font, null_texture: u32, text_atlas_texture: u32) !Batches {
        var all_vertices = ArrayList(Vertex).init(arena_allocator);
        var all_elements = ArrayList(u16).init(arena_allocator);
        var batches = ArrayList(Batch).init(arena_allocator);

        defer {
            all_vertices.deinit();
            all_elements.deinit();
            batches.deinit();
        }

        // var shape_cmd: ?*ShapeCommand = first_shape_cmd;
        var current_clip: shape2d.Rect = .{
            .x = 0,
            .y = 0,
            .w = screen_width,
            .h = screen_height,
        };

        var max_element: u16 = 0;
        var current_texture = null_texture;
        var is_text = false;
        for (shape_cmds.items) |sc, sc_index| {
            // while (shape_cmd) |sc| {
            switch (sc.command) {
                .clip => |clp| {
                    current_clip = clp;
                    // shape_cmd = sc.next;
                    continue;
                },
                .line => @panic("line not implemented"),
                .triangle => |tri| {
                    current_texture = null_texture;
                    is_text = false;
                    _ = tri;
                    @panic("triangle not implemented");
                },
                .rectangle => |rect| {
                    current_texture = null_texture;
                    is_text = false;

                    try all_vertices.appendSlice(&Vertex.createQuad(rect.dim.x, rect.dim.y, rect.dim.w, rect.dim.h, rect.color));
                    var elements = Vertex.quadIndices();
                    max_element = Device.offsetElementsBy(max_element, &elements) + 1;
                    try all_elements.appendSlice(&elements);
                },
                .circle => |cir| {
                    current_texture = null_texture;
                    is_text = false;
                    _ = cir;
                    @panic("circle not implemented");
                },
                .text => |txt| {
                    current_texture = text_atlas_texture;
                    is_text = true;

                    var vertices = try arena_allocator.alloc(Vertex, 4 * txt.string.len);
                    var elements = try arena_allocator.alloc(u16, txt.string.len * 6);
                    _ = Vertex.manyQuadIndices(@intCast(u16, txt.string.len), elements);
                    var vertex_index: u64 = 0;
                    var x = txt.x;
                    var y = txt.y;
                    var space_to_next_line: f32 = 0;
                    for (txt.string) |char| {
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
                            txt.color,
                        );
                        std.mem.copy(Vertex, vertices[vertex_index..], &vs);
                        vertex_index += vs.len;

                        x += @intToFloat(f32, g.advance);

                        if (char == '\n') {
                            x = txt.x;
                            y += font.newLineOffset();
                        }
                    }

                    max_element = Device.offsetElementsBy(max_element, elements) + 1;
                    try all_vertices.appendSlice(vertices);
                    try all_elements.appendSlice(elements);
                },
            }

            var end_the_batch = false;
            if (sc_index == shape_cmds.items.len - 1) end_the_batch = true else {
                var next_texture = switch (shape_cmds.items[sc_index + 1].command) {
                    .text => text_atlas_texture,
                    else => null_texture,
                };

                const same_clip = switch (shape_cmds.items[sc_index + 1].command) {
                    .clip => |next_clp| current_clip.eql(next_clp),
                    else => true,
                };
                if (current_texture != next_texture or !same_clip)
                    end_the_batch = true;
            }

            if (end_the_batch) {
                try batches.append(.{
                    .clip = current_clip,
                    .vertices_end_index = all_vertices.items.len,
                    .elements_end_index = all_elements.items.len,
                    .texture = current_texture,
                    .is_text = is_text,
                });
            }
        }
        return .{
            .vertices = try all_vertices.toOwnedSlice(),
            .elements = try all_elements.toOwnedSlice(),
            .batches = try batches.toOwnedSlice(),
        };
    }
};
