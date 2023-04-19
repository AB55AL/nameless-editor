const std = @import("std");
const print = std.debug.print;

const globals = @import("../globals.zig");
const editor = globals.editor;
const ui = globals.ui;
const input = @import("input.zig");
const buffer_ops = @import("buffer_ops.zig");

const notify = @import("../ui/notify.zig");
const buffer_ui = @import("../ui/buffer.zig");

pub fn scrollDown() void {
    var fb = ui.focused_buffer_window orelse return;
    fb.scrollDown(1);
}

pub fn scrollUp() void {
    var fb = ui.focused_buffer_window orelse return;
    fb.scrollUp(1);
}

pub fn cycleWindows() void {
    buffer_ui.nextBufferWindow();
}

pub fn deleteBackward() void {
    var fbw = &(buffer_ops.focusedBW() orelse return).data;
    const index = fbw.buffer.getIndex(fbw.cursor);
    const old_size = fbw.buffer.size();

    fbw.buffer.deleteBefore(index) catch |err| {
        print("input_layer.deleteBackward()\n\t{}\n", .{err});
    };

    const deleted_bytes = old_size - fbw.buffer.size();
    fbw.cursor = fbw.buffer.getRowAndCol(index - deleted_bytes);
}

pub fn deleteForward() void {
    var fbw = &(buffer_ops.focusedBW() orelse return).data;
    const index = fbw.buffer.getIndex(fbw.cursor);
    fbw.buffer.deleteAfterCursor(index) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}

pub fn toggleCommandLine() void {
    if (editor.command_line_is_open)
        editor.command_line.close()
    else
        editor.command_line.open();
}
