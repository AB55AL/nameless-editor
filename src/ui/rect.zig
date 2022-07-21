const std = @import("std");
const print = std.debug.print;

const c = @import("../c.zig");
const Shader = @import("shaders.zig").Shader;
const vectors = @import("vectors.zig");
const matrices = @import("matrices.zig");

const indices = [_]u32{
    0, 1, 3, // first triangle
    1, 2, 3, // second triangle
};

var vertices = [12]f32{
    0.5, 1.0, 0.0, // top right
    0.5, -1.0, 0.0, // bottom right
    -0.5, -1.0, 0.0, // bottom left
    -0.5, 1.0, 0.0, // top left
};

pub const Rect = @This();

VAO: u32,
VBO: u32,
EBO: u32,

shader: Shader,

pub fn init(shader: Shader) Rect {
    var rect: Rect = undefined;

    rect.shader = shader;
    rect.createVaoVboAndEbo();
    return rect;
}

pub fn createVaoVboAndEbo(rect: *Rect) void {
    rect.shader.use();
    var VAO: u32 = undefined;
    c.glGenVertexArrays(1, &VAO);
    c.glBindVertexArray(VAO);

    var VBO: u32 = undefined;
    c.glGenBuffers(1, &VBO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, c.GL_STATIC_DRAW);

    // never unbind EBO before VAO
    var EBO: u32 = undefined;
    c.glGenBuffers(1, &EBO);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, EBO);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * indices.len, &indices, c.GL_STATIC_DRAW);

    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 3 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(0);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    rect.VAO = VAO;
    rect.VBO = VBO;
    rect.EBO = EBO;
}

pub fn render(rect: Rect, x_coord: f32, y_coord: f32, width: f32, height: f32, color: vectors.vec3) void {
    rect.shader.use();
    c.glBindVertexArray(rect.VAO);

    var x = x_coord;
    var y = y_coord;
    var w = width;
    var h = height;

    // zig fmt: off
    var position = [12]f32{
        x + w, y    , 0.0, // top right
        x + w, y + h, 0.0, // bottom right
        x    , y + h, 0.0, // bottom left
        x    , y    , 0.0, // top left
    };
    // zig fmt: on

    c.glBindBuffer(c.GL_ARRAY_BUFFER, rect.VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32) * position.len, &position, c.GL_STATIC_DRAW);

    c.glUniform3f(c.glGetUniformLocation(rect.shader.ID, "cursorColor"), color.x, color.y, color.z);

    c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
}
