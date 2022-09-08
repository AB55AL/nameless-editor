const glfw = @import("glfw");
const c = @import("c.zig");

const input = @import("../editor/input.zig");
const Renderer = @import("renderer.zig");

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
    window.setFramebufferSizeCallback(Renderer.framebufferSizeCallback);
    window.setCharCallback(input.characterInputCallback);
    window.setKeyCallback(input.keyInputCallback);
    window.setCursorPosCallback(Renderer.cursorPositionCallback);
    window.setScrollCallback(Renderer.scrollCallback);

    return window;
}

pub fn deinit(window: *glfw.Window) void {
    window.destroy();
    glfw.terminate();
}
