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
    fbw.buffer.deleteBefore(index, 1) catch |err| {
        print("input_layer.deleteBackward()\n\t{}\n", .{err});
    };

    // var focused_buffer_window = ui.focused_buffer_window orelse return;
    // focused_buffer_window.setWindowCursorToBuffer();
}

pub fn deleteForward() void {
    var fbw = &(buffer_ops.focusedBW() orelse return).data;
    const index = fbw.buffer.getIndex(fbw.cursor);
    fbw.buffer.deleteAfterCursor(index, 1) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}

pub fn moveRight() void {
    var fbw = &(buffer_ops.focusedBW() orelse return).data;
    const pos = fbw.cursor.moveRelativeColumn(fbw.buffer, 1, false);
    fbw.cursor = pos.rowCol();
    fbw.buffer.resetSelection();
}

pub fn moveLeft() void {
    var fbw = &(buffer_ops.focusedBW() orelse return).data;
    const pos = fbw.cursor.moveRelativeColumn(fbw.buffer, -1, false);
    fbw.cursor = pos.rowCol();
    fbw.buffer.resetSelection();
}

pub fn moveUp() void {
    var fbw = &(buffer_ops.focusedBW() orelse return).data;

    const pos = fbw.cursor.moveRelativeRow(fbw.buffer, -1);
    fbw.cursor = pos.rowCol();
    fbw.buffer.resetSelection();
}

pub fn moveDown() void {
    var fbw = &(buffer_ops.focusedBW() orelse return).data;

    const pos = fbw.cursor.moveRelativeRow(fbw.buffer, 1);
    fbw.cursor = pos.rowCol();
    fbw.buffer.resetSelection();
}

pub fn toggleCommandLine() void {
    if (editor.command_line_is_open)
        editor.command_line.close()
    else
        editor.command_line.open();
}
