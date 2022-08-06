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
const layouts = @import("layouts.zig");
const Layout = layouts.Layout;
const LayoutInterface = layouts.LayoutInterface;
const Layouts = layouts.Layouts;

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

    pub fn newIndex() u32 {
        const index = next_window_index;
        next_window_index += 1;
        return index;
    }
};

pub const Windows = struct {
    wins: ArrayList(Window),
    focused_window_index: u32,
    active_layout: Layout,

    pub fn focusedWindow(windows: *Windows) *Window {
        assert(windows.wins.items.len > 0);

        var wins = windows.wins.items;
        for (wins) |*win|
            if (win.index == windows.focused_window_index) return win;

        return &wins[0];
    }

    pub fn focusedWindowArrayIndex(windows: *Windows) usize {
        assert(windows.wins.items.len > 0);
        for (windows.wins.items) |win, i|
            if (win.index == windows.focused_window_index) return i;

        return 0;
    }

    pub fn windowArrayIndex(windows: *Windows, window_index: u32) usize {
        assert(windows.wins.items.len > 0);
        for (windows.wins.items) |win, i|
            if (win.index == window_index)
                return i;

        return 0;
    }

    pub fn changeFocusedWindow(windows: *Windows, dir: window_ops.Direction) void {
        if (global.command_line_is_open.*) return;
        var layout = windows.active_layout.layout;
        layout.changeFocusedWindow(layout.impl_struct, windows, dir);
        global.focused_buffer = windows.focusedWindow().buffer;
    }

    pub fn openWindow(windows: *Windows, dir: window_ops.Direction) Allocator.Error!*Window {
        return try windows.active_layout.layout.openWindow(
            windows.active_layout.layout.impl_struct,
            windows,
            dir,
        );
    }
    pub fn closeWindow(windows: *Windows, window_index: u32) void {
        windows.active_layout.layout.closeWindow(
            windows.active_layout.layout.impl_struct,
            windows,
            window_index,
        );

        if (windows.wins.items.len == 0) return;
        // TODO: change this to be the top of the window history stack. When implemented
        windows.focused_window_index = windows.wins.items[0].index;
    }
    pub fn resize(windows: *Windows, window_index: u32, resize_value: f32, dir: window_ops.Direction) void {
        windows.active_layout.layout.resize(
            windows.active_layout.layout.impl_struct,
            windows,
            window_index,
            resize_value,
            dir,
        );
    }
    pub fn equalize(windows: *Windows) void {
        windows.active_layout.layout.equalize(
            windows.active_layout.layout.impl_struct,
            windows,
        );
    }

    pub fn cycleThroughWindows(windows: *Windows, dir: window_ops.Direction) void {
        if (global.command_line_is_open.*) return;

        windows.active_layout.layout.cycleThroughWindows(
            windows.active_layout.layout.impl_struct,
            windows,
            dir,
        );

        global.focused_buffer = windows.focusedWindow().buffer;
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    //
    // Finding neighbors
    //
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
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
