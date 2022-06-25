const std = @import("std");
const fs = std.fs;
const c = @cImport({
    @cInclude("glad/glad.h");
});

pub const Shader = @This();

ID: u32,

/// Returns the ID of a Shader struct
pub fn init(comptime vertex_file_path: []const u8, comptime fragment_file_path: []const u8) !Shader {
    var success: c_int = undefined;
    // var infoLog: [512]u8 = undefined;

    const vertex_code align(8) = @embedFile(vertex_file_path);
    const fragment_code align(8) = @embedFile(fragment_file_path);

    const vertex = c.glCreateShader(c.GL_VERTEX_SHADER);
    defer c.glDeleteShader(vertex);
    c.glShaderSource(vertex, 1, @ptrCast([*]const [*]const u8, &vertex_code), null);
    c.glCompileShader(vertex);

    const fragment = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    defer c.glDeleteShader(fragment);
    c.glShaderSource(fragment, 1, @ptrCast([*]const [*]const u8, &fragment_code), null);
    c.glCompileShader(fragment);

    c.glGetShaderiv(vertex, c.GL_COMPILE_STATUS, &success);
    c.glGetShaderiv(fragment, c.GL_COMPILE_STATUS, &success);

    const ID = c.glCreateProgram();
    c.glAttachShader(ID, vertex);
    c.glAttachShader(ID, fragment);
    c.glLinkProgram(ID);

    c.glGetProgramiv(ID, c.GL_LINK_STATUS, &success);

    return Shader{
        .ID = ID,
    };
}

pub fn use(shader: Shader) void {
    c.glUseProgram(shader.ID);
}
