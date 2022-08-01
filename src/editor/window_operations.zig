const globals = @import("../globals.zig");
const command_line = @import("command_line.zig");
const Windows = @import("command_line.zig");

const global = globals.global;
const internal = globals.internal;

pub const Direction = enum(u3) {
    here,
    right,
    left,
    above,
    below,
};

pub fn cycleThroughWindows() void {
    if (internal.windows.wins.items.len == 0) return;
    if (global.command_line_is_open) command_line.close();
    const static = struct {
        var i: usize = 0;
    };
    static.i += 1;
    if (static.i >= internal.windows.wins.items.len) static.i = 0;
    global.focused_buffer = internal.windows.wins.items[static.i].buffer;
}

pub fn closeFocusedWindow() void {
    internal.windows.closeFocusedWindow();
}

pub fn focusWindow(dir: Direction) void {
    internal.windows.focusWindow(dir);
}
