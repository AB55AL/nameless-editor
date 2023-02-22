const std = @import("std");
const print = std.debug.print;

const c = @import("c.zig");
const math = @import("math.zig");
const DrawCommand = @import("draw_command.zig").DrawCommand;
const Batches = @import("draw_command.zig").Batches;
const DrawList = @import("draw_command.zig").DrawList;

pub const Device = @This();

const ProgramType = enum {
    vertex,
    fragment,
    program,
};

pub const Vertex = struct {
    position: math.Vec2(f32),
    color: math.Vec3(f32),
    texture_uv: math.Vec2(f32),

    // zig fmt: off
    pub fn createQuad(x: f32, y: f32, w: f32, h: f32, color: u24) [4]Vertex {
        const colo = math.hexToColorVector(color);
        const v0 = .{ .position = .{ .x = x + w, .y = y + h }, .color = colo, .texture_uv = .{ .x = 1, .y = 0 } };
        const v1 = .{ .position = .{ .x = x + w, .y = y     }, .color = colo, .texture_uv = .{ .x = 1, .y = 1 } };
        const v2 = .{ .position = .{ .x = x,     .y = y     }, .color = colo, .texture_uv = .{ .x = 0, .y = 1 } };
        const v3 = .{ .position = .{ .x = x,     .y = y + h }, .color = colo, .texture_uv = .{ .x = 0, .y = 0 } };

        return .{ v0, v1, v2, v3 };
    }

    pub fn createQuadUV(x: f32, y: f32, w: f32, h: f32, top_left: math.Vec2(f32), bottom_right: math.Vec2(f32), color: u24) [4]Vertex {
        const colo = math.hexToColorVector(color);
        const top_right = math.Vec2(f32){ .x = bottom_right.x, .y = top_left.y };
        const bottom_left = math.Vec2(f32){ .x = top_left.x, .y = bottom_right.y };

        const v0 = .{ .position = .{ .x = x + w, .y = y + h }, .color = colo, .texture_uv = top_right };
        const v1 = .{ .position = .{ .x = x + w, .y = y     }, .color = colo, .texture_uv = bottom_right };
        const v2 = .{ .position = .{ .x = x,     .y = y     }, .color = colo, .texture_uv = bottom_left };
        const v3 = .{ .position = .{ .x = x,     .y = y + h }, .color = colo, .texture_uv = top_left };

        return .{ v0, v1, v2, v3 };
    }

    pub fn createTriangle(p0: math.Vec2(f32), p1: math.Vec2(f32), p2: math.Vec2(f32), color: u24) [3]Vertex {
        const colo = math.hexToColorVector(color);
        const v0 = .{ .position = p0, .color = colo, .texture_uv = .{ .x = 1, .y = 1 } };
        const v1 = .{ .position = p1, .color = colo, .texture_uv = .{ .x = 1, .y = 0 } };
        const v2 = .{ .position = p2, .color = colo, .texture_uv = .{ .x = 0, .y = 0 } };
        return .{ v0, v1, v2 };
    }

    pub fn createCircle(mid_point_x: f32, mid_point_y: f32, radius: f32, comptime sides: f32, color: u24) [sides * 3]Vertex {
        var circle_points: [sides]math.Vec2(f32) = undefined;
        var a: f32 = 0;
        var j: u32 = 0;
        while (a < 360) : (a += (360 / sides)) {
            const heading = a * (std.math.pi / 180.0);
            const cx = std.math.cos(heading) * radius + mid_point_x;
            const cy = std.math.sin(heading) * radius + mid_point_y;
            circle_points[j] = .{ .x = cx, .y = cy };
            j += 1;
        }

        j = 0;
        var i: u32 = 0;
        var circle_vertices: [sides * 3]Vertex = undefined;
        while (i < circle_points.len) : (i += 1) {
            if (i == circle_points.len - 1) {
                const vertices = Vertex.createTriangle(
                    .{.x = mid_point_x, .y = mid_point_y},
                    .{.x = circle_points[circle_points.len - 1].x, .y = circle_points[circle_points.len - 1].y},
                    .{ .x =  circle_points[0].x, .y = circle_points[0].y },
                    color,
                );
                std.mem.copy(Vertex, circle_vertices[circle_vertices.len - 3 ..], &vertices);
            } else {
                const vertices = Vertex.createTriangle(
                    .{.x = mid_point_x, .y = mid_point_y },
                    .{.x = circle_points[i].x, .y = circle_points[i].y },
                    .{.x = circle_points[i + 1].x, .y = circle_points[i + 1].y},
                    color,
                );
                std.mem.copy(Vertex, circle_vertices[j .. j + 3], &vertices);
            }

            j += 3;
        }
        return circle_vertices;
    }
    // zig fmt: on

    pub fn quadIndices() [6]u16 {
        return .{ 0, 1, 2, 2, 3, 0 };
    }

    pub fn manyQuadIndices(num_of_quads: u64, out: []u16) []u16 {
        std.debug.assert(out.len >= num_of_quads * 6);

        var i: u32 = 0;
        var element: u16 = 0;
        while (i < num_of_quads * 6) : (i += 6) {
            out[i] = element;
            out[i + 1] = element + 1;
            out[i + 2] = element + 2;

            out[i + 3] = element + 2;
            out[i + 4] = element + 3;
            out[i + 5] = element;

            element += 4;
        }

        return out[0..i];
    }

    pub fn triangleIndices() [3]u16 {
        return .{ 0, 1, 2 };
    }

    pub fn circleIndices(comptime sides: u32) [sides * 3]u16 {
        var array: [sides * 3]u16 = undefined;
        for (array, 0..) |_, i| array[i] = @intCast(u16, i);
        return array;
    }
};

const fragment_source =
    \\#version 330 core
    \\precision mediump float;
    \\uniform sampler2D Texture;
    \\
    \\in vec2 Frag_UV;
    \\in vec4 Frag_Color;
    \\
    \\out vec4 Out_Color;
    \\uniform bool is_text;
    \\
    \\void main(){
    \\ vec4 texture = texture(Texture, Frag_UV.st);
    \\ if (is_text) {
    \\  Out_Color = Frag_Color * texture.r;
    \\ } else {
    \\  Out_Color = Frag_Color * texture;
    \\ }
    \\}
;

const vertex_source =
    \\#version 330 core
    \\layout (location = 0) in vec2 Position;
    \\layout (location = 1) in vec3 Color;
    \\layout (location = 2) in vec2 TexCoord;
    \\
    \\uniform mat4 ProjMtx;
    \\
    \\out vec2 Frag_UV;
    \\out vec4 Frag_Color;
    \\
    \\void main() {
    \\  Frag_UV = TexCoord;
    \\  Frag_Color = vec4(Color.xyz, 1);
    \\
    \\  gl_Position = ProjMtx * vec4(Position.xy, 0, 1);
    \\
    \\}
;

vao: u32,
vbo: u32,
ebo: u32,

texture_location: c_int,
projection_location: c_int,
is_text_location: c_int,

program: u32,

pub fn init() Device {
    var device: Device = undefined;

    device.program = compileShaders();
    c.glUseProgram(device.program);

    device.texture_location = c.glGetUniformLocation(device.program, "Texture");
    device.projection_location = c.glGetUniformLocation(device.program, "ProjMtx");
    device.is_text_location = c.glGetUniformLocation(device.program, "is_text");

    c.glGenVertexArrays(1, &device.vao);
    c.glGenBuffers(1, &device.vbo);
    c.glGenBuffers(1, &device.ebo);

    c.glBindVertexArray(device.vao);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, device.vbo);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, device.ebo);

    // position attribute
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @intToPtr(*allowzero anyopaque, @offsetOf(Vertex, "position")));
    // color attribute
    c.glEnableVertexAttribArray(1);
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @intToPtr(*allowzero anyopaque, @offsetOf(Vertex, "color")));
    // texture coord attribute
    c.glEnableVertexAttribArray(2);
    c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(Vertex), @intToPtr(*allowzero anyopaque, @offsetOf(Vertex, "texture_uv")));

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);

    c.glBindTexture(c.GL_TEXTURE_2D, 0);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    return device;
}

fn compileShaders() u32 {
    const vertex = c.glCreateShader(c.GL_VERTEX_SHADER);
    defer c.glDeleteShader(vertex);
    c.glShaderSource(vertex, 1, @ptrCast([*]const [*]const u8, &vertex_source), null);
    c.glCompileShader(vertex);
    checkCompileErrors(vertex, .vertex);

    const fragment = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    defer c.glDeleteShader(fragment);
    c.glShaderSource(fragment, 1, @ptrCast([*]const [*]const u8, &fragment_source), null);
    c.glCompileShader(fragment);
    checkCompileErrors(fragment, .fragment);

    const id = c.glCreateProgram();
    c.glAttachShader(id, vertex);
    c.glAttachShader(id, fragment);
    c.glLinkProgram(id);

    checkCompileErrors(id, .program);

    c.glDeleteShader(vertex);
    c.glDeleteShader(fragment);

    return id;
}

fn checkCompileErrors(shader: u32, pt: ProgramType) void {
    var success: i32 = undefined;
    var info_log: [1024]u8 = undefined;
    var info_log_len: c_int = undefined;
    if (pt != .program) {
        c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            c.glGetShaderInfoLog(shader, 1024, &info_log_len, &info_log);
            print("{}\n\t{s}\n", .{ pt, info_log[0..@intCast(u32, info_log_len)] });
            @panic("TODO: error handle");
        }
    } else {
        c.glGetShaderiv(shader, c.GL_LINK_STATUS, &success);
        if (success == 0) {
            c.glGetShaderInfoLog(shader, 1024, &info_log_len, &info_log);
            print("{}\n\t{s}\n", .{ pt, info_log[0..@intCast(u32, info_log_len)] });
            @panic("TODO: error handle");
        }
    }
}

pub fn copyVerticesAndElementsToOpenGL(device: *Device, list: *DrawList) void {
    c.glBindVertexArray(device.vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, device.vbo);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, device.ebo);

    const v_size = @intCast(c_long, @sizeOf(Vertex) * list.vertices.items.len);
    const e_size = @intCast(c_long, @sizeOf(u16) * list.elements.items.len);

    c.glBufferData(c.GL_ARRAY_BUFFER, v_size, list.vertices.items.ptr, c.GL_DYNAMIC_DRAW);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, e_size, list.elements.items.ptr, c.GL_DYNAMIC_DRAW);

    _ = c.glUnmapBuffer(c.GL_ARRAY_BUFFER);
    _ = c.glUnmapBuffer(c.GL_ELEMENT_ARRAY_BUFFER);
}

pub fn offsetElementsBy(offset: u16, elements: []u16) u16 {
    var max_element: u16 = 0;
    for (elements, 0..) |_, i| {
        elements[i] += offset;
        max_element = std.math.max(max_element, elements[i]);
    }

    return max_element;
}
