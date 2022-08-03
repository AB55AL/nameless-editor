const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Buffer = @import("../editor/buffer.zig");
const VCursor = @import("vcursor.zig").VCursor;
const globals = @import("../globals.zig");
const utils = @import("../editor/utils.zig");
const vectors = @import("vectors.zig");
const window_ops = @import("window_ops.zig");

const global = globals.global;
const internal = globals.internal;

var next_window_index: u32 = 0;

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
    index: u32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    background_color: vectors.vec3 = .{ .x = 0.1, .y = 0.1, .z = 0.1 },

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

    pub fn newIndex() u32 {
        const index = next_window_index;
        next_window_index += 1;
        return index;
    }
};

pub const Windows = struct {
    wins: ArrayList(Window),
    focused_window_index: u32,

    pub fn focusedWindow(windows: *Windows) *Window {
        assert(windows.wins.items.len > 0);

        var wins = windows.wins.items;
        for (wins) |*win|
            if (win.index == windows.focused_window_index) return win;

        return &wins[0];
    }

    pub fn focusedWindowArrayIndex(windows: *Windows) ?usize {
        var wins = windows.wins.items;
        if (wins.len == 0) return null;
        for (wins) |win, i|
            if (win.index == windows.focused_window_index) return i;

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

        const window = Window{
            .index = Window.newIndex(),
            .x = 0,
            .y = 0,
            .width = 1,
            .height = 1,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        };
        windows.focused_window_index = window.index;
        try windows.wins.append(window);
    }
    pub fn createRight(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }

        var focused = windows.focusedWindow();
        const window = Window{
            .index = Window.newIndex(),
            .x = focused.x + focused.width / 2,
            .y = focused.y,
            .width = focused.width / 2,
            .height = focused.height,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        };
        windows.focused_window_index = window.index;
        try windows.wins.append(window);

        focused.width /= 2;
    }
    pub fn createLeft(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }

        var focused = windows.focusedWindow();
        const window = Window{
            .index = Window.newIndex(),
            .x = focused.x,
            .y = focused.y,
            .width = focused.width / 2,
            .height = focused.height,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        };
        windows.focused_window_index = window.index;
        try windows.wins.append(window);

        focused.width /= 2;
        focused.x += focused.width;
    }
    pub fn createAbove(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }

        var focused = windows.focusedWindow();
        const window = Window{
            .index = Window.newIndex(),
            .x = focused.x,
            .y = focused.y,
            .width = focused.width,
            .height = focused.height / 2,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        };
        windows.focused_window_index = window.index;
        try windows.wins.append(window);

        focused.height /= 2;
        focused.y += focused.height;
    }
    pub fn createBelow(windows: *Windows, buffer: *Buffer) Allocator.Error!void {
        if (windows.wins.items.len == 0) {
            try windows.createNew(buffer);
            return;
        }
        var focused = windows.focusedWindow();
        const window = Window{
            .index = next_window_index,
            .x = focused.x,
            .y = focused.y + focused.height / 2,
            .width = focused.width,
            .height = focused.height / 2,
            .buffer = buffer,
            .start_col = 1,
            .start_row = 1,
        };
        windows.focused_window_index = window.index;
        try windows.wins.append(window);

        focused.height /= 2;
    }

    pub fn focusWindow(windows: *Windows, dir: window_ops.Direction) void {
        if (windows.wins.items.len <= 1) return;
        switch (dir) {
            .right => {
                var neighbor = windows.closestRightNeighbor(windows.focusedWindow()) orelse return;
                global.focused_buffer = neighbor.buffer;
                windows.focused_window_index = neighbor.index;
            },
            .left => {
                var neighbor = windows.closestLeftNeighbor(windows.focusedWindow()) orelse return;
                global.focused_buffer = neighbor.buffer;
                windows.focused_window_index = neighbor.index;
            },
            .above => {
                var neighbor = windows.closestAboveNeighbor(windows.focusedWindow()) orelse return;
                global.focused_buffer = neighbor.buffer;
                windows.focused_window_index = neighbor.index;
            },

            .below => {
                var neighbor = windows.closestBelowNeighbor(windows.focusedWindow()) orelse return;
                global.focused_buffer = neighbor.buffer;
                windows.focused_window_index = neighbor.index;
            },
            else => return,
        }
    }

    pub fn closeWindow(windows: *Windows, index: usize) void {
        if (windows.wins.items.len == 0) return;
        for (windows.wins.items) |win, i| {
            if (win.index == index) {
                var removed = internal.windows.wins.orderedRemove(i);
                windows.resize(&removed);
            }
        }
    }

    pub fn closeFocusedWindow(windows: *Windows) void {
        if (windows.wins.items.len == 0) return;
        windows.resize(windows.focusedWindow());
        windows.closeWindow(windows.focusedWindow().index);
    }

    pub fn resize(windows: *Windows, target: *Window) void {
        if (windows.wins.items.len == 1) {
            target.x = 0;
            target.y = 0;
            target.width = 1;
            target.height = 1;
        } else {
            var wins_vertical_to_resize = windows.findBottomNeighbors(target) orelse
                windows.findTopNeighbors(target);

            var wins_horizontal_to_resize = windows.findRightNeighbors(target) orelse
                windows.findLeftNeighbors(target);

            // Make sure that a window doesn't resize vertically and draw over other window
            if (wins_horizontal_to_resize != null and wins_vertical_to_resize != null) {
                for (wins_vertical_to_resize.?) |win| {
                    if (!utils.inRange(f32, win.x + win.width, target.x, target.x + target.width)) {
                        internal.allocator.free(wins_vertical_to_resize.?);
                        wins_vertical_to_resize = null;
                    }
                }
            }

            if (wins_vertical_to_resize) |wins| {
                defer internal.allocator.free(wins_vertical_to_resize.?);
                for (wins) |win| {
                    if (win.y > target.y) {
                        win.y = target.y;
                        win.height = target.height + win.height;
                    } else {
                        win.height = target.height + win.height;
                    }
                }
                return;
            }

            if (wins_horizontal_to_resize) |wins| {
                defer internal.allocator.free(wins_horizontal_to_resize.?);
                for (wins) |win| {
                    if (win.x > target.x) {
                        win.x = target.x;
                        win.width = target.width + win.width;
                    } else {
                        win.width = target.width + win.width;
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

    fn closestRightNeighbor(windows: *Windows, target_window: *Window) ?*Window {
        var neighbor: ?*Window = null;

        for (windows.wins.items) |*win| {
            if (win.x == target_window.x + target_window.width) {
                if (neighbor == null)
                    neighbor = win
                else if (win.x <= neighbor.?.x)
                    neighbor = win;
            }
        }

        return neighbor;
    }
    fn closestLeftNeighbor(windows: *Windows, target_window: *Window) ?*Window {
        var neighbor: ?*Window = null;

        for (windows.wins.items) |*win| {
            if (win.x + win.width == target_window.x) {
                if (neighbor == null)
                    neighbor = win
                else if (win.x >= neighbor.?.x)
                    neighbor = win;
            }
        }

        return neighbor;
    }
    fn closestAboveNeighbor(windows: *Windows, target_window: *Window) ?*Window {
        var neighbor: ?*Window = null;

        for (windows.wins.items) |*win| {
            if (win.y + win.height == target_window.y) {
                if (neighbor == null)
                    neighbor = win
                else if (win.y >= neighbor.?.y)
                    neighbor = win;
            }
        }

        return neighbor;
    }
    fn closestBelowNeighbor(windows: *Windows, target_window: *Window) ?*Window {
        var neighbor: ?*Window = null;

        for (windows.wins.items) |*win| {
            if (win.y == target_window.y + target_window.height) {
                if (neighbor == null)
                    neighbor = win
                else if (win.y <= neighbor.?.y)
                    neighbor = win;
            }
        }

        return neighbor;
    }
};
