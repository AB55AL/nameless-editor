const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const core = @import("core");

const command_line = core.command_line;
const globals = core.globals;

const ui = @import("ui/ui.zig");
const ui_glfw = @import("ui/glfw.zig");
const ui_debug = @import("ui/debug.zig");

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

    _ = glfw.init(.{});
    var window = glfw.Window.create(800, 800, "test", null, null, .{}).?;
    defer window.destroy();

    glfw.makeContextCurrent(window);
    window.setKeyCallback(ui_glfw.keyCallback);
    window.setCharCallback(ui_glfw.charCallback);

    imgui.init(allocator);
    defer imgui.deinit();


    _ = imgui.io.addFontFromFileWithConfig("assets/Fira Code Light Nerd Font Complete Mono.otf", 22, null, null);
    // _ = imgui.io.addFontFromFileWithConfig("assets/Amiri-Regular.ttf", 30, null, &[_]u16{ 0x20, 0xFFFF, 0 });

    imgui.backend.init(window.handle, true, "#version 330");
    defer imgui.backend.deinit();

    while (!window.shouldClose()) {
        defer {
            if (globals.internal.extra_frames > 0) globals.internal.extra_frames -= 1;

            globals.input.key_queue.resize(0) catch unreachable;
            globals.input.char_queue.resize(0) catch unreachable;
        }

        var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_instance.deinit();
        const arena = arena_instance.allocator();

        if (globals.internal.extra_frames != 0) glfw.pollEvents() else glfw.waitEvents();

        imgui.backend.newFrame();

        input_layer.handleInput();

        imgui.io.setConfigFlags(.{ .nav_enable_keyboard = false });
        const window_size = window.getSize();
        if (globals.ui.gui_full_size) {
            imgui.setNextWindowSize(.{ .w = @intToFloat(f32, window_size.width), .h = @intToFloat(f32, window_size.height) });
            globals.ui.gui_full_size = false;
        }

        try ui.buffers(allocator);

        imgui.io.setConfigFlags(.{ .nav_enable_keyboard = true });
        if (globals.ui.imgui_demo) {
            imgui.showDemoWindow(&globals.ui.imgui_demo);
            core.extraFrames(.two);
        }
        if (globals.ui.inspect_editor) ui_debug.inspectEditor(arena);

        var iter = globals.ui.user_ui.keyIterator();
        while (iter.next()) |f|
            (f.*)(allocator, arena);

        imgui.backend.draw(window_size.width, window_size.height);

        window.swapBuffers();
    }
}
