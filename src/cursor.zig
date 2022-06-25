const std = @import("std");
const print = std.debug.print;

const c = @import("c.zig");
const shaders = @import("shaders.zig");
const vectors = @import("vectors.zig");
const matrices = @import("matrices.zig");

pub const Cursor = @This();

row: i32,
col: i32,

VAO: u32,
VBO: u32,
EBO: u32,

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

pub fn init(shader: shaders.Shader) Cursor {
    var cursor: Cursor = undefined;

    cursor.row = 1;
    cursor.col = 1;
    shader.use();
    cursor.createVaoVboAndEbo();

    return cursor;
}

pub fn createVaoVboAndEbo(cursor: *Cursor) void {
    var VAO: u32 = undefined;
    c.glGenVertexArrays(1, &VAO);
    c.glBindVertexArray(VAO);

    var VBO: u32 = undefined;
    c.glGenBuffers(1, &VBO);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32) * vertices.len, &vertices, c.GL_STATIC_DRAW);

    // neven unbind EBO before VAO
    var EBO: u32 = undefined;
    c.glGenBuffers(1, &EBO);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, EBO);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(u32) * indices.len, &indices, c.GL_STATIC_DRAW);

    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 3 * @sizeOf(f32), null);
    c.glEnableVertexAttribArray(0);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    cursor.VAO = VAO;
    cursor.VBO = VBO;
    cursor.EBO = EBO;
}

pub fn render(cursor: Cursor, shader: shaders.Shader, x_coord: i32, y_coord: i32, width: i32, height: i32, color: vectors.vec3) void {
    shader.use();
    c.glBindVertexArray(cursor.VAO);

    var x = @intToFloat(f32, x_coord);
    var y = @intToFloat(f32, y_coord);
    var w = @intToFloat(f32, width);
    var h = @intToFloat(f32, height);

    // zig fmt: off
    var position = [12]f32{
        x + w, y    , 0.0, // top right
        x + w, y + h, 0.0, // bottom right
        x    , y + h, 0.0, // bottom left
        x    , y    , 0.0, // top left
    };
    // zig fmt: on

    c.glBindBuffer(c.GL_ARRAY_BUFFER, cursor.VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32) * position.len, &position, c.GL_STATIC_DRAW);

    c.glUniform3f(c.glGetUniformLocation(shader.ID, "cursorColor"), color.x, color.y, color.z);

    c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
}
