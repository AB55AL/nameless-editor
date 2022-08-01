pub const Buffer = @import("editor/buffer.zig");
pub const Cursor = @import("editor/cursor.zig");
pub const history = @import("editor/history.zig");
pub const command_line = @import("editor/command_line.zig");
pub usingnamespace @import("editor/buffer_operations.zig");
pub usingnamespace @import("editor/window_operations.zig");

const globals = @import("globals.zig");
pub const Global = @import("globals.zig").Global;

pub const global = globals.global;
