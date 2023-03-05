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
const gui = @import("gui");
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

    var win_backend = try gui.SDLBackend.init(800, 600);
    defer win_backend.deinit();

    var win = gui.Window.init(@src(), 0, allocator, win_backend.guiBackend());
    defer win.deinit();

    main_loop: while (true) {
        var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();

        var nstime = win.beginWait(win_backend.hasEvent());
        try win.begin(arena, nstime);
        win_backend.clear();

        const quit = try win_backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // try gui.label(@src(), 0, "fps {d:4.2}", .{gui.FPS()}, .{ .gravity_x = 1.0, .color_text = ui.toColor(0xFFFFFF, 255) });

        if (globals.editor.command_line_is_open) {
            var cmd_win = &globals.ui.command_line_buffer_window;

            const static = struct {
                var rect = gui.Rect{ .x = 500, .y = 500, .w = 200, .h = 50 };
            };
            var fw = try gui.floatingWindow(@src(), 0, false, &static.rect, null, .{});
            defer fw.deinit();
            try ui.bufferWidget(@src(), 0, cmd_win, true, .{ .expand = .both });
        }

        buffers: {
            var bw_tree = globals.ui.visiable_buffers_tree orelse {
                command_line.open();
                break :buffers;
            };

            var box = try gui.boxEqual(@src(), 0, .horizontal, .{ .expand = .both });
            var rect = box.wd.rect;
            defer box.deinit();

            var windows = try bw_tree.getAndSetWindows(arena, rect);
            for (windows, 0..) |bw, i| {
                try ui.bufferWidget(@src(), i, bw, false, .{ .rect = bw.rect });
            }
        }

        const end_micros = try win.end();

        win_backend.setCursor(win.cursorRequested());

        win_backend.renderPresent();

        const wait_event_micros = win.waitTime(end_micros, 60);

        win_backend.waitEventTimeout(wait_event_micros);
    }
}
