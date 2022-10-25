const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;

const Buffer = @import("../editor/buffer.zig");
const VCursor = @import("vcursor.zig").VCursor;
const globals = @import("../globals.zig");
const utils = @import("../editor/utils.zig");
const vectors = @import("vectors.zig");
const window_ops = @import("window_ops.zig");

const global = globals.global;
const internal = globals.internal;

pub const WindowOptions = struct {
    wrap_text: bool = false,
};

pub const OSWindow = struct {
    width: f32,
    height: f32,
};

/// coords and dimensions of a window in pixels
pub const WindowPixels = struct {
    pub fn convert(window: Window) WindowPixels {
        return .{
            .x = window.x * internal.os_window.width,
            .y = window.y * internal.os_window.height,
            .width = window.width * internal.os_window.width,
            .height = window.height * internal.os_window.height,
        };
    }

    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const Window = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    /// color in hex
    background_color: u24 = 0x11_11_11,

    buffer: *Buffer = undefined,
    start_col: u32 = 1,
    start_row: u32 = 1,
    /// Number of rows to render
    num_of_rows: u32 = std.math.maxInt(u16),
    /// Number of rows that have been rendered
    visible_rows: u32 = 0,
    /// Number of cols that have been rendered at buffer.cursor.row
    visible_cols_at_buffer_row: u32 = 0,

    options: WindowOptions = .{},
};
