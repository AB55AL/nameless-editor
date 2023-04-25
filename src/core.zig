pub const Buffer = @import("editor/buffer.zig");
pub const command_line = @import("editor/command_line.zig");
pub const input = @import("editor/input.zig");
pub const common_input_functions = @import("editor/common_input_functions.zig");
pub const registers = @import("editor/registers.zig");
pub const Hooks = @import("editor/hooks.zig");
pub usingnamespace @import("editor/editor.zig");
pub usingnamespace @import("ui/notify.zig");
pub usingnamespace @import("editor/buffer_window.zig");

pub const globals = @import("globals.zig");

pub const motions = @import("extras/motions.zig");
pub const utils = @import("utils.zig");
pub const utf8 = @import("utf8.zig");

pub fn extraFrame() void {
    globals.internal.extra_frame = true;
}

pub fn addUserUI(func: globals.UserUIFunc) void {
    _ = globals.ui.user_ui.getOrPut(func) catch return;
}

pub fn removeUserUI(func: globals.UserUIFunc) void {
    _ = globals.ui.user_ui.remove(func);
}
