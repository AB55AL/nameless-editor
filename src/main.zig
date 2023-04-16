const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const core = @import("core");

const command_line = core.command_line;
const globals = core.globals;

const ui = @import("ui/ui.zig");

const input_layer = @import("input_layer");
const imgui = @import("imgui");
const options = @import("options");
const user = @import("user");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try globals.initGlobals(allocator);
    defer globals.deinitGlobals();

    try input_layer.init();
    defer input_layer.deinit();

    try command_line.init();
    defer command_line.deinit();

    if (options.user_config_loaded) try user.init();
    defer if (options.user_config_loaded) user.deinit();

    /////////////////////
    {
        var buffer = try core.openBufferFP("src/main.zig", null);
        try buffer.insertAt(10, "HEY THERE");
    }
    /////////////////////

    _ = glfw.init(.{});
    var window = glfw.Window.create(800, 800, "test", null, null, .{}).?;
    defer window.destroy();
    glfw.makeContextCurrent(window);

    imgui.init(allocator);
    defer imgui.deinit();

    imgui.io.setConfigFlags(.{ .nav_enable_keyboard = true });

    _ = imgui.io.addFontFromFileWithConfig("assets/Fira Code Light Nerd Font Complete Mono.otf", 22, null, null);
    // _ = imgui.io.addFontFromFileWithConfig("assets/Amiri-Regular.ttf", 30, null, &[_]u16{ 0x20, 0xFFFF, 0 });

    imgui.backend.init(window.handle, true, "#version 330");
    defer imgui.backend.deinit();

    var show_demo_window = true;
    while (!window.shouldClose()) {
        // glfw.waitEvents();

        imgui.backend.newFrame();

        imgui.showDemoWindow(&show_demo_window);

        const window_size = window.getSize();
        imgui.setNextWindowSize(.{ .w = @intToFloat(f32, window_size.width), .h = @intToFloat(f32, window_size.height) });
        imgui.setNextWindowPos(.{ .x = 0, .y = 0 });
        try ui.buffers(allocator);

        if (globals.editor.command_line_is_open) {
            _ = imgui.begin("command line", .{
                .flags = .{ .no_nav_focus = true, .no_scroll_with_mouse = true, .no_scrollbar = true },
            });
            defer imgui.end();

            const size = imgui.getWindowSize();
            ui.bufferWidget(&globals.ui.command_line_buffer_window.data, size[0], size[1]);
        }

        glfw.pollEvents();
        ui.handleTextInput();
        try ui.handleKeyInput(allocator);

        imgui.backend.draw(window_size.width, window_size.height);

        window.swapBuffers();
    }
}
