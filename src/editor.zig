pub const Buffer = @import("editor/buffer.zig");
pub const command_line = @import("editor/command_line.zig");
pub const window = @import("ui/window.zig");
pub usingnamespace @import("editor/buffer_ops.zig");
pub usingnamespace @import("ui/window_ops.zig");
pub const input = @import("editor/input.zig");

const globals = @import("globals.zig");
pub const global = globals.global;
