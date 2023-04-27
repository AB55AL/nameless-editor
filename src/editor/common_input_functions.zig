const std = @import("std");
const print = std.debug.print;

const globals = @import("../globals.zig");
const ui = globals.ui;
const input = @import("input.zig");
const editor = @import("editor.zig");

const notify = @import("../ui/notify.zig");
const buffer_window = @import("buffer_window.zig");

pub fn scrollDown() void {
    var fb = ui.focused_buffer_window orelse return;
    fb.scrollDown(1);
}

pub fn scrollUp() void {
    var fb = ui.focused_buffer_window orelse return;
    fb.scrollUp(1);
}

pub fn cycleWindows() void {
    buffer_window.nextBufferWindow();
}

pub fn deleteBackward() void {
    var f = editor.focusedBufferAndBW() orelse return;

    const index = f.buffer.getIndex(f.bw.data.cursor());
    const old_size = f.buffer.size();

    f.buffer.deleteBefore(index) catch |err| {
        print("input_layer.deleteBackward()\n\t{}\n", .{err});
    };

    const deleted_bytes = old_size - f.buffer.size();
    f.bw.data.setCursor(f.buffer.getPoint(index - deleted_bytes));
}

pub fn deleteForward() void {
    var f = editor.focusedBufferAndBW() orelse return;
    const index = f.buffer.getIndex(f.bw.data.cursor());
    f.buffer.deleteAfterCursor(index) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}

pub fn toggleCommandLine() void {
    if (editor.cliOpen())
        editor.command_line.close()
    else
        editor.command_line.open();
}
