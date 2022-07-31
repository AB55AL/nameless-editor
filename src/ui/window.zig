const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Buffer = @import("../buffer.zig");
const VCursor = @import("vcursor.zig").VCursor;
const global_types = @import("../global_types.zig");
const Global = global_types.Global;
const GlobalInternal = global_types.GlobalInternal;
const utils = @import("../utils.zig");
const vectors = @import("vectors.zig");

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

    background_color: vectors.vec3 = .{ .x = 0, .y = 0, .z = 0 },

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
        assert(windows.wins.items.len > 0);
        var wins = windows.wins.items;
        return &wins[windows.focusedWindowIndex().?];
    }

    pub fn focusedWindowIndex(windows: *Windows) ?usize {
        var wins = windows.wins.items;
        for (wins) |win, i|
            if (win.buffer.index.? == global.focused_buffer.index.?)
                return i;

        return 0;
    }

    pub fn changeCurrentWindow(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0)
            try windows.createNew(buffer)
        else
            windows.focusedWindow().buffer = buffer;
    }

    pub fn createNew(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len != 0) return;

        var r = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var g = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var b = @mod(std.crypto.random.float(f32), 0.5) + 0.2;

        try windows.wins.append(Window{
            .x = 0,
            .y = 0,
            .width = 1,
            .height = 1,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
            .background_color = .{ .x = r, .y = g, .z = b },
        });
    }
    pub fn createRight(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }

        var r = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var g = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var b = @mod(std.crypto.random.float(f32), 0.5) + 0.2;

        var focused = windows.focusedWindow();
        try windows.wins.append(Window{
            .x = focused.x + focused.width / 2,
            .y = focused.y,
            .width = focused.width / 2,
            .height = focused.height,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
            .background_color = .{ .x = r, .y = g, .z = b },
        });

        focused.width /= 2;
    }
    pub fn createLeft(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }

        var r = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var g = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var b = @mod(std.crypto.random.float(f32), 0.5) + 0.2;

        var focused = windows.focusedWindow();
        try windows.wins.append(Window{
            .x = focused.x,
            .y = focused.y,
            .width = focused.width / 2,
            .height = focused.height,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
            .background_color = .{ .x = r, .y = g, .z = b },
        });

        focused.width /= 2;
        focused.x += focused.width;
    }
    pub fn createAbove(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }

        var r = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var g = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var b = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        print("{d}\n", .{r});
        print("{d}\n", .{g});
        print("{d}\n", .{b});

        var focused = windows.focusedWindow();
        try windows.wins.append(Window{
            .x = focused.x,
            .y = focused.y,
            .width = focused.width,
            .height = focused.height / 2,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
            .background_color = .{ .x = r, .y = g, .z = b },
        });

        focused.height /= 2;
        focused.y += focused.height;
    }
    pub fn createBelow(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }

        var r = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var g = @mod(std.crypto.random.float(f32), 0.5) + 0.2;
        var b = @mod(std.crypto.random.float(f32), 0.5) + 0.2;

        var focused = windows.focusedWindow();
        try windows.wins.append(Window{
            .x = focused.x,
            .y = focused.y + focused.height / 2,
            .width = focused.width,
            .height = focused.height / 2,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
            .background_color = .{ .x = r, .y = g, .z = b },
        });

        focused.height /= 2;
    }

    pub fn closeWindow(windows: *Windows, index: usize) void {
        if (windows.wins.items.len == 0) return;
        _ = internal.windows.wins.orderedRemove(index);
    }

    pub fn closeFocusedWindow(windows: *Windows) void {
        if (windows.wins.items.len == 0) return;
        const index = windows.focusedWindowIndex().?;
        windows.resize();
        windows.closeWindow(index);
    }

    pub fn resize(windows: *Windows) void {
        var focused = windows.focusedWindow();
        if (windows.wins.items.len == 1) {
            focused.x = 0;
            focused.y = 0;
            focused.width = 1;
            focused.height = 1;
        } else {
            var wins_vertical_to_resize = windows.findBottomNeighbors(focused) orelse
                windows.findTopNeighbors(focused);

            if (wins_vertical_to_resize) |wins| {
                defer internal.allocator.free(wins_vertical_to_resize.?);
                for (wins) |win| {
                    if (win.y > focused.y) {
                        win.y = focused.y;
                        win.height = focused.height + win.height;
                    } else {
                        win.height = focused.height + win.height;
                    }
                }
                return;
            }

            var wins_horizontal_to_resize = windows.findRightNeighbors(focused) orelse
                windows.findLeftNeighbors(focused);

            if (wins_horizontal_to_resize) |wins| {
                defer internal.allocator.free(wins_horizontal_to_resize.?);
                for (wins) |win| {
                    if (win.x > focused.x) {
                        win.x = focused.x;
                        win.width = focused.width + win.width;
                    } else {
                        win.width = focused.width + win.width;
                    }
                }
                return;
            }
        }
    }

    fn findBottomNeighbors(windows: *Windows, current_window: *Window) ?[]*Window {
        var neighbors = ArrayList(*Window).initCapacity(internal.allocator, internal.windows.wins.items.len) catch |err| {
            print("findBottomNeighbors(): err={}\n", .{err});
            return null;
        };

        for (windows.wins.items) |*win| {
            if (!utils.inRange(
                f32,
                win.x,
                current_window.x,
                current_window.x + current_window.width,
            )) continue;
            if (!utils.inRange(
                f32,
                win.x + win.width,
                current_window.x,
                current_window.x + current_window.width,
            )) continue;

            if (win.y == current_window.y + current_window.height)
                neighbors.append(win) catch |err| {
                    print("findBottomNeighbors(): err={}\n", .{err});
                    neighbors.deinit();
                    return null;
                };
        }

        if (neighbors.items.len == 0) {
            neighbors.deinit();
            return null;
        }

        return neighbors.toOwnedSlice();
    }

    fn findTopNeighbors(windows: *Windows, current_window: *Window) ?[]*Window {
        var neighbors = ArrayList(*Window).initCapacity(internal.allocator, internal.windows.wins.items.len) catch |err| {
            print("findTopNeighbors(): err={}\n", .{err});
            return null;
        };

        for (windows.wins.items) |*win| {
            if (!utils.inRange(
                f32,
                win.x,
                current_window.x,
                current_window.x + current_window.width,
            )) continue;
            if (!utils.inRange(
                f32,
                win.x + win.width,
                current_window.x,
                current_window.x + current_window.width,
            )) continue;

            if (win.y + win.height == current_window.y)
                neighbors.append(win) catch |err| {
                    print("findTopNeighbors(): err={}\n", .{err});
                    neighbors.deinit();
                    return null;
                };
        }

        if (neighbors.items.len == 0) {
            neighbors.deinit();
            return null;
        }

        return neighbors.toOwnedSlice();
    }

    fn findRightNeighbors(windows: *Windows, current_window: *Window) ?[]*Window {
        var neighbors = ArrayList(*Window).initCapacity(internal.allocator, internal.windows.wins.items.len) catch |err| {
            print("findRightNeighbors(): err={}\n", .{err});
            return null;
        };

        for (windows.wins.items) |*win| {
            if (!utils.inRange(
                f32,
                win.y,
                current_window.y,
                current_window.y + current_window.height,
            )) continue;

            if (win.x == current_window.x + current_window.width)
                neighbors.append(win) catch |err| {
                    print("findRightNeighbors(): err={}\n", .{err});
                    neighbors.deinit();
                    return null;
                };
        }

        if (neighbors.items.len == 0) {
            neighbors.deinit();
            return null;
        }

        return neighbors.toOwnedSlice();
    }

    fn findLeftNeighbors(windows: *Windows, current_window: *Window) ?[]*Window {
        var neighbors = ArrayList(*Window).initCapacity(internal.allocator, internal.windows.wins.items.len) catch |err| {
            print("findLeftNeighbors(): err={}\n", .{err});
            return null;
        };

        for (windows.wins.items) |*win| {
            if (!utils.inRange(
                f32,
                win.y,
                current_window.y,
                current_window.y + current_window.height,
            )) continue;

            if (win.x + win.width == current_window.x)
                neighbors.append(win) catch |err| {
                    print("findLeftNeighbors(): err={}\n", .{err});
                    neighbors.deinit();
                    return null;
                };
        }

        if (neighbors.items.len == 0) {
            neighbors.deinit();
            return null;
        }

        return neighbors.toOwnedSlice();
    }
};
