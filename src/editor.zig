pub const Buffer = @import("editor/buffer.zig");
pub const command_line = @import("editor/command_line.zig");
pub const input = @import("editor/input.zig");
pub usingnamespace @import("editor/buffer_ops.zig");
pub usingnamespace @import("ui/notify.zig");
pub usingnamespace @import("ui/buffer.zig");

const globals = @import("globals.zig");
pub const editor = globals.editor;
pub const ui = globals.ui;
