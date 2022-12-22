const std = @import("std");
const print = std.debug.print;

const glfw = @import("glfw");
const c = @import("c.zig");

const editor = @import("../globals.zig").editor;
const ui = @import("../globals.zig").ui;
const Device = @import("device.zig");
const input = @import("../editor/glfw_input.zig");
const math = @import("math.zig");

const GLFW = @This();

window: glfw.Window,

pub fn init(window_width: u32, window_height: u32) !glfw.Window {
    try glfw.init(.{});
    var window = try glfw.Window.create(window_width, window_height, "TestWindow", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_profile = glfw.Window.Hints.OpenGLProfile.opengl_core_profile,
    });
    try glfw.makeContextCurrent(window);

    _ = c.gladLoadGLLoader(@ptrCast(c.GLADloadproc, &glfw.getProcAddress));
    c.glViewport(0, 0, @intCast(c_int, window_width), @intCast(c_int, window_height));

    // callbacks
    window.setCharCallback(input.characterInputCallback);
    window.setKeyCallback(input.keyInputCallback);
    window.setMouseButtonCallback(input.mouseCallback);

    return window;
}

pub fn deinit(window: *glfw.Window) void {
    window.destroy();
    glfw.terminate();
}

pub fn updateSize(window: glfw.Window, device: Device) void {
    const size = window.getSize() catch return;
    var projection = math.createOrthoMatrix(0, @intToFloat(f32, size.width), @intToFloat(f32, size.height), 0, -1, 1);
    ui.state.window_width = size.width;
    ui.state.window_height = size.height;
    c.glUniformMatrix4fv(device.projection_location, 1, c.GL_FALSE, &projection);
    c.glViewport(0, 0, @intCast(c_int, size.width), @intCast(c_int, size.height));
}
