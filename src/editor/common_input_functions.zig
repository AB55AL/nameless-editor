const std = @import("std");
const print = std.debug.print;

const globals = @import("../globals.zig");
const editor = globals.editor;
const ui = globals.ui;
const input = @import("input.zig");

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
    var fb = editor.focused_buffer orelse return;
    fb.deleteBeforeCursor(1) catch |err| {
        print("input_layer.deleteBackward()\n\t{}\n", .{err});
    };

    var focused_buffer_window = ui.focused_buffer_window orelse return;
    focused_buffer_window.setWindowCursorToBuffer();
}

pub fn deleteForward() void {
    var fb = editor.focused_buffer orelse return;
    fb.deleteAfterCursor(1) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}
pub fn moveRight() void {
    var fb = ui.focused_buffer_window orelse return;
    fb.moveCursorRelativeColumn(1, false, true);
}
pub fn moveLeft() void {
    var fb = ui.focused_buffer_window orelse return;
    fb.moveCursorRelativeColumn(-1, false, true);
}
pub fn moveUp() void {
    var fb = ui.focused_buffer_window orelse return;
    fb.moveCursorRelativeRow(-1, true);
}
pub fn moveDown() void {
    var fb = ui.focused_buffer_window orelse return;
    fb.moveCursorRelativeRow(1, true);
}

pub fn toggleCommandLine() void {
    if (editor.command_line_is_open)
        editor.command_line.close()
    else
        editor.command_line.open();
}
