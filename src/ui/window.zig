const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const Buffer = @import("../buffer.zig");
const VCursor = @import("vcursor.zig").VCursor;
const global_types = @import("../global_types.zig");
const Global = global_types.Global;
const GlobalInternal = global_types.GlobalInternal;

extern var global: Global;
extern var internal: GlobalInternal;

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

    buffer: *Buffer,
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

pub const Windows = struct {
    wins: ArrayList(Window),

    pub fn focusedWindow(windows: *Windows) *Window {
        var wins = windows.wins.items;
        var i: usize = 0;
        while (i < wins.len) : (i += 1)
            if (wins[i].buffer.index.? == global.focused_buffer.index.?)
                return &wins[i];

        return &wins[0];
    }

    pub fn createNew(windows: *Windows, buffer: *Buffer) !void {
        if (windows.wins.items.len != 0) return;

        try windows.wins.append(Window{
            .x = 0,
            .y = 0,
            .width = 1,
            .height = 1,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        });
    }
    pub fn createRight(windows: *Windows, buffer: *Buffer) !void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }
        var focused = windows.focusedWindow();
        try windows.wins.append(Window{
            .x = focused.x + focused.width / 2,
            .y = focused.y,
            .width = focused.width / 2,
            .height = focused.height,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        });

        focused.width /= 2;
    }
    pub fn createLeft(windows: *Windows, buffer: *Buffer) !void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }
        var focused = windows.focusedWindow();
        try windows.wins.append(Window{
            .x = focused.x,
            .y = focused.y,
            .width = focused.width / 2,
            .height = focused.height,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        });

        focused.width /= 2;
        focused.x += focused.width;
    }
    pub fn createAbove(windows: *Windows, buffer: *Buffer) !void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }
        var focused = windows.focusedWindow();
        try windows.wins.append(Window{
            .x = focused.x,
            .y = focused.y,
            .width = focused.width,
            .height = focused.height / 2,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        });

        focused.height /= 2;
        focused.y += focused.height;
    }
    pub fn createBelow(windows: *Windows, buffer: *Buffer) !void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }
        var focused = windows.focusedWindow();
        try windows.wins.append(Window{
            .x = focused.x,
            .y = focused.y + focused.height / 2,
            .width = focused.width,
            .height = focused.height / 2,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        });

        focused.height /= 2;
    }
};
