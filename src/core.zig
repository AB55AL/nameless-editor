pub const Buffer = @import("editor/buffer.zig");
pub const command_line = @import("editor/command_line.zig");
pub const input = @import("editor/input.zig");
pub const common_input_functions = @import("editor/common_input_functions.zig");
pub const registers = @import("editor/registers.zig");
pub usingnamespace @import("editor/buffer_ops.zig");
pub usingnamespace @import("ui/notify.zig");
pub usingnamespace @import("ui/buffer.zig");

pub const globals = @import("globals.zig");
pub const editor = globals.editor;
pub const ui = globals.ui;

pub const motions = @import("extras/motions.zig");
pub const utils = @import("utils.zig");
pub const utf8 = @import("utf8.zig");

pub fn extraFrames(extra: enum { one, two, inf }) void {
    switch (extra) {
        .one => if (globals.internal.extra_frames <= 0) {
            globals.internal.extra_frames = 1;
        },
        .two => globals.internal.extra_frames = 2,
        .inf => globals.internal.extra_frames = -1,
    }
}
