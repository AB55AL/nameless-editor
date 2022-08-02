pub const Buffer = @import("editor/buffer.zig");
pub const Cursor = @import("editor/cursor.zig");
pub const history = @import("editor/history.zig");
pub const command_line = @import("editor/command_line.zig");
pub usingnamespace @import("editor/buffer_ops.zig");
pub usingnamespace @import("ui/window_ops.zig");

const globals = @import("globals.zig");
pub const Global = @import("globals.zig").Global;

pub const global = globals.global;
