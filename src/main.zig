const std = @import("std");
const print = std.debug.print;
const time = std.time;
const ArrayList = std.ArrayList;

const glfw = @import("glfw");
const Buffer = @import("editor/buffer.zig");
const command_line = @import("editor/command_line.zig");
const glfw_window = @import("ui/glfw.zig");
const buffer_ops = @import("editor/buffer_ops.zig");
const globals = @import("globals.zig");
const Device = @import("ui/device.zig");
const ui = @import("ui/ui.zig");
const shape2d = @import("ui/shape2d.zig");
const c = @import("ui/c.zig");
const draw_command = @import("ui/draw_command.zig");

const input_layer = @import("input_layer");
const options = @import("options");
const user = @import("user");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
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

    if (globals.editor.first_buffer == null) {
        var buffer = try buffer_ops.createPathLessBuffer();
        globals.editor.focused_buffer = buffer;
        _ = try buffer_ops.openBufferI(buffer.index);
    }

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
        c.glClearColor(0.5, 0.5, 0.5, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        glfw_window.updateSize(window, device);
        var pos = window.getCursorPos() catch glfw.Window.CursorPos{ .xpos = 0, .ypos = 0 };
        globals.ui.state.mousex = @floatCast(f32, pos.xpos);
        globals.ui.state.mousey = @floatCast(f32, pos.ypos);

        ui.begin();

        var string = "This\nworks very nice\narstoierastie arstienarioesniaersnoa\nand spaces do work";
        var dim = ui.stringDimension(string);
        try ui.container(globals.internal.allocator, .{ .x = 0, .y = 0, .w = @intToFloat(f32, globals.ui.state.window_width), .h = @intToFloat(f32, globals.ui.state.window_height) });
        if (try ui.buttonText(allocator, .column_wise, "hey")) {
            print("hey\n", .{});
        }

        try ui.textWithDim(allocator, string, dim, &.{ .clickable, .draggable, .clip, .highlight_text });

        ui.end();

        //
        // Render
        //
        {
            var arena = std.heap.ArenaAllocator.init(globals.internal.allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            c.glEnable(c.GL_BLEND);
            c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
            c.glBlendEquation(c.GL_FUNC_ADD);
            c.glDisable(c.GL_CULL_FACE);
            c.glDisable(c.GL_DEPTH_TEST);
            c.glEnable(c.GL_SCISSOR_TEST);
            c.glActiveTexture(c.GL_TEXTURE0);

            c.glUseProgram(device.program);
            c.glUniform1i(device.texture_location, 0);

            var all_batches = try draw_command.Batches.shapeCommandToBatches(
                arena_allocator,
                @intToFloat(f32, globals.ui.state.window_height),
                @intToFloat(f32, globals.ui.state.window_height),
                globals.ui.state.shape_cmds,
                globals.ui.state.font,
                null_texture,
                globals.ui.state.font.atlas.texture_id,
            );

            device.copyVerticesAndElementsToOpenGL(all_batches);

            c.glBindVertexArray(device.vao);
            c.glBindBuffer(c.GL_ARRAY_BUFFER, device.vbo);
            c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, device.ebo);

            var offset: u32 = 0;
            for (all_batches.batches) |batch, i| {
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

                c.glBindTexture(c.GL_TEXTURE_2D, batch.texture);

                var element_count = if (i == 0) batch.elements_end_index else batch.elements_end_index - all_batches.batches[i - 1].elements_end_index;

                c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, element_count), c.GL_UNSIGNED_SHORT, @intToPtr(*allowzero anyopaque, offset));
                offset += @intCast(u16, element_count) * @sizeOf(u16);
                // try window.swapBuffers();
                // std.time.sleep(100000000 * 5);
            }

            // reset the shape_cmds array
            globals.ui.state.shape_cmds.deinit();
            globals.ui.state.shape_cmds = ArrayList(shape2d.ShapeCommand).init(globals.internal.allocator);
            try shape2d.ShapeCommand.pushClip(0, 0, @intToFloat(f32, globals.ui.state.window_width), @intToFloat(f32, globals.ui.state.window_height));

            c.glUseProgram(0);
            c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
            c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, 0);
            c.glBindVertexArray(0);
            c.glDisable(c.GL_BLEND);
            c.glDisable(c.GL_SCISSOR_TEST);
        }

        try window.swapBuffers();
        try glfw.pollEvents();
        if (globals.editor.valid_buffers_count == 0) window.setShouldClose(true);
    }
}
