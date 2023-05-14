const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const core = @import("core");

const command_line = core.command_line;
const globals = core.globals;

const editor_ui = @import("ui/editor_ui.zig");
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

    _ = glfw.init(.{});
    var window = glfw.Window.create(800, 800, "test", null, null, .{}).?;
    defer window.destroy();

    glfw.makeContextCurrent(window);
    window.setKeyCallback(ui_glfw.keyCallback);
    window.setCharCallback(ui_glfw.charCallback);

    imgui.init(allocator);
    defer imgui.deinit();

    imgui.backend.init(window.handle, true, "#version 330");
    defer imgui.backend.deinit();

    if (options.user_config_loaded) try user.init();
    defer if (options.user_config_loaded) user.deinit();

    var timer = try std.time.Timer.start();
    while (!window.shouldClose()) {
        defer {
            globals.internal.key_queue.resize(0) catch unreachable;
            globals.internal.char_queue.resize(0) catch unreachable;

            globals.ui.notifications.clearDone(timer.read());
            timer.reset();
        }

        var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_instance.deinit();
        const arena = arena_instance.allocator();

        if (globals.internal.extra_frames > 0)
            glfw.pollEvents()
        else if (globals.ui.notifications.count() > 0)
            glfw.waitEventsTimeout(1)
        else {
            glfw.waitEvents();
            core.extraFrames();
        }

        globals.internal.extra_frames -|= 1;

        imgui.backend.newFrame();

        input_layer.handleInput(&globals.internal.key_queue, &globals.internal.char_queue);

        imgui.io.setConfigFlags(.{ .nav_enable_keyboard = false });
        const window_size = window.getSize();

        try editor_ui.buffers(arena, @intToFloat(f32, window_size.width), @intToFloat(f32, window_size.height));
        editor_ui.notifications();

        imgui.io.setConfigFlags(.{ .nav_enable_keyboard = true });
        if (globals.ui.imgui_demo) {
            imgui.showDemoWindow(&globals.ui.imgui_demo);
            core.extraFrames();
        }
        if (globals.ui.inspect_editor) ui_debug.inspectEditor(arena);

        var iter = globals.ui.user_ui.keyIterator();
        while (iter.next()) |f|
            (f.*)(allocator, arena);

        imgui.backend.draw(window_size.width, window_size.height);

        window.swapBuffers();
    }
}
