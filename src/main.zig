const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const Buffer = @import("editor/buffer.zig");
const command_line = @import("editor/command_line.zig");
const glfw_window = @import("ui/glfw.zig");
const buffer_ops = @import("editor/buffer_ops.zig");
const buffer_ui = @import("ui/buffer.zig");
const globals = @import("globals.zig");
const Device = @import("ui/device.zig");
const ui_lib = @import("ui/ui_lib.zig");
const shape2d = @import("ui/shape2d.zig");
const c = @import("ui/c.zig");
const draw_command = @import("ui/draw_command.zig");
const notify = @import("ui/notify.zig");
const math = @import("ui/math.zig");
const DrawList = @import("ui/draw_command.zig").DrawList;

const input_layer = @import("input_layer");
const options = @import("options");
const user = @import("user");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const window_width: u32 = 800;
    const window_height: u32 = 600;
    const allocator = gpa.allocator();

    var window = try glfw_window.init(window_width, window_height);
    defer glfw_window.deinit(&window);

    try globals.initGlobals(allocator, window_width, window_height);
    defer globals.deinitGlobals();

    try input_layer.init();
    defer input_layer.deinit();

    try command_line.init();
    defer command_line.deinit();

    if (options.user_config_loaded) try user.init();
    defer if (options.user_config_loaded) user.deinit();

    var device = Device.init();

    // TODO: delete this
    var null_texture: u32 = undefined;
    {
        var dd: [3]u8 = undefined;
        dd[0] = 0xFF;
        dd[1] = 0xFF;
        dd[2] = 0xFF;
        c.glGenTextures(1, &null_texture);
        c.glBindTexture(c.GL_TEXTURE_2D, null_texture);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGB, 1, 1, 0, c.GL_RGB, c.GL_UNSIGNED_BYTE, &dd);
    }

    while (!window.shouldClose()) {
        const current_frame_start_time = std.time.nanoTimestamp();
        defer {
            var loop_time = std.time.nanoTimestamp() - current_frame_start_time;
            for (globals.ui.notifications.slice()) |*n|
                n.remaining_time -= (@intToFloat(f32, loop_time) / 1000000);

            var slice = globals.ui.notifications.slice();
            if (slice.len > 0) {
                var i: i64 = @intCast(i64, slice.len - 1);
                while (i >= 0) : (i -= 1) {
                    var n = slice[@intCast(u64, i)];
                    if (n.remaining_time <= 0)
                        _ = globals.ui.notifications.remove(@intCast(u64, i));
                }
            }
        }
        defer std.time.sleep(1000000 * 17); // 60-ish FPS
        // defer std.time.sleep(1000000 * 50);
        c.glClearColor(0.5, 0.5, 0.5, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        glfw_window.updateSize(window, device);
        var pos = window.getCursorPos() catch glfw.Window.CursorPos{ .xpos = 0, .ypos = 0 };
        globals.ui.state.mousex = @floatCast(f32, pos.xpos);
        globals.ui.state.mousey = @floatCast(f32, pos.ypos);

        try bulidUI(allocator);
        render(&device, null_texture);

        // Reset the ArrayLists
        globals.ui.state.draw_list.deinit();
        globals.ui.state.draw_list = DrawList.init(allocator);

        try window.swapBuffers();
        try glfw.pollEvents();
        // if (globals.editor.valid_buffers_count == 0) window.setShouldClose(true);
    }
}

fn bulidUI(allocator: std.mem.Allocator) !void {
    ui_lib.beginUI();

    var passes = [_]ui_lib.State.Pass{ .layout, .input_and_render };
    for (passes) |pass| {
        globals.ui.state.pass = pass;
        defer globals.ui.state.max_id = 1;

        const ww = @intToFloat(f32, globals.ui.state.window_width);
        const wh = @intToFloat(f32, globals.ui.state.window_height);
        try ui_lib.container(allocator, ui_lib.DynamicRow.getLayout(), .{ .x = 0, .y = 0, .w = ww, .h = wh });

        try ui_lib.layoutStart(allocator, ui_lib.DynamicColumn.getLayout(), ww, wh, 0xAA0000);
        try buffer_ui.buffers(allocator);
        try ui_lib.layoutEnd(ui_lib.DynamicColumn.getLayout());

        globals.ui.state.max_id = 200;
        if (globals.editor.command_line_is_open) {
            var buffer_window = &globals.ui.command_line_buffer_window;
            var dim = math.Vec2(f32){
                .x = @intToFloat(f32, globals.ui.state.window_width),
                .y = globals.ui.state.font.newLineOffset() * @intToFloat(f32, buffer_window.buffer.lines.newlines_count),
            };
            try buffer_ui.bufferWidget(allocator, buffer_window, dim);
        }

        ui_lib.containerEnd();

        if (!globals.ui.notifications.empty()) {
            globals.ui.state.max_id = 2000;
            try ui_lib.container(allocator, ui_lib.DynamicRow.getLayout(), .{ .x = ww - 500, .y = 0, .w = ww, .h = wh });
            try notify.notifyWidget(allocator);
            ui_lib.containerEnd();
        }

        if (pass == .layout) {
            var widget_tree = globals.ui.state.first_widget_tree;
            while (widget_tree) |wt| {
                {
                    const depth = wt.treeDepth(0);
                    var j: u32 = 0;
                    while (j <= depth) : (j += 1)
                        wt.capSubtreeToParentRect(j);
                }
                {
                    const depth = wt.treeDepth(0);
                    var j: u32 = 0;
                    while (j <= depth) : (j += 1)
                        wt.applyLayouts(j);
                }
                widget_tree = wt.next_sibling;
            }
        }
    }

    ui_lib.endUI();
    print("======================================================UI END=======================================================\n", .{});
}

fn render(device: *Device, null_texture: u32) void {
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glBlendEquation(c.GL_FUNC_ADD);
    c.glDisable(c.GL_CULL_FACE);
    c.glDisable(c.GL_DEPTH_TEST);
    c.glEnable(c.GL_SCISSOR_TEST);
    c.glActiveTexture(c.GL_TEXTURE0);

    c.glUseProgram(device.program);
    c.glUniform1i(device.texture_location, 0);

    device.copyVerticesAndElementsToOpenGL(&globals.ui.state.draw_list);

    c.glBindVertexArray(device.vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, device.vbo);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, device.ebo);

    var offset: u32 = 0;
    for (globals.ui.state.draw_list.batches.items) |batch| {
        if (batch.is_text) {
            c.glUniform1i(device.is_text_location, 1);
        } else {
            c.glUniform1i(device.is_text_location, 0);
        }

        c.glScissor(
            @floatToInt(c_int, batch.clip.x),
            @intCast(c_int, globals.ui.state.window_height) - @floatToInt(c_int, batch.clip.y + batch.clip.h),
            @floatToInt(c_int, batch.clip.w),
            @floatToInt(c_int, batch.clip.h),
        );

        if (batch.texture == 0)
            c.glBindTexture(c.GL_TEXTURE_2D, null_texture)
        else
            c.glBindTexture(c.GL_TEXTURE_2D, batch.texture);

        var element_count = batch.elements_count;

        c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, element_count), c.GL_UNSIGNED_SHORT, @intToPtr(*allowzero anyopaque, offset));
        offset += @intCast(u16, element_count) * @sizeOf(u16);
        // try window.swapBuffers();
        // std.time.sleep(100000000 * 5);
    }

    c.glUseProgram(0);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);
    c.glDisable(c.GL_BLEND);
    c.glDisable(c.GL_SCISSOR_TEST);
}
