const std = @import("std");
const print = std.debug.print;

const c = @import("../c.zig");
const Shader = @import("shaders.zig").Shader;
const vectors = @import("../vectors.zig");
const matrices = @import("../matrices.zig");

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

pub const CursorRenderInfo = @This();

VAO: u32,
VBO: u32,
EBO: u32,

shader: Shader,

pub fn init(shader: Shader) CursorRenderInfo {
    var cri: CursorRenderInfo = undefined;

    shader.use();
    cri.createVaoVboAndEbo();

    return cri;
}

pub fn createVaoVboAndEbo(cri: *CursorRenderInfo) void {
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

    cri.VAO = VAO;
    cri.VBO = VBO;
    cri.EBO = EBO;
}

pub fn render(cri: CursorRenderInfo, x_coord: i32, y_coord: i32, width: i32, height: i32, color: vectors.vec3) void {
    cri.shader.use();
    c.glBindVertexArray(cri.VAO);

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

    c.glBindBuffer(c.GL_ARRAY_BUFFER, cri.VBO);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32) * position.len, &position, c.GL_STATIC_DRAW);

    c.glUniform3f(c.glGetUniformLocation(cri.shader.ID, "cursorColor"), color.x, color.y, color.z);

    c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
}
