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

pub const Layouts = struct {
    layouts: ArrayList(Layout),

    pub fn init(allocator: Allocator) Layouts {
        return .{
            .layouts = ArrayList(Layout).init(allocator),
        };
    }

    pub fn deinit(layouts: *Layouts) void {
        for (layouts.layouts.items) |layout|
            layouts.layouts.allocator.free(layout.type_name);

        layouts.layouts.deinit();
    }

    pub fn remove(layouts: *Layouts, layout_name: []const u8) void {
        if (layouts.layouts.items.len == 1) {
            print("Can't remove layout when only one is left\n", .{});
            return;
        }

        for (layouts.layouts.items) |layout, i| {
            if (eql(layout.name, layout_name)) {
                var l = layouts.layouts.swapRemove(i);
                internal.allocator.free(l.name);
            }
        }
    }
    pub fn add(layouts: *Layouts, iface: LayoutInterface, impl_struct: anytype) !void {
        var type_name = try utils.typeToStringAlloc(internal.allocator, @TypeOf(impl_struct));
        var layout = Layout{
            .layout = iface,
            .type_name = type_name,
        };
        try layouts.layouts.append(layout);
    }
};

pub const Layout = struct {
    layout: LayoutInterface,
    type_name: []const u8,
};

pub const LayoutInterface = struct {
    impl_struct: *anyopaque,

    openWindow: fn (iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) Allocator.Error!*Window,
    closeWindow: fn (iface: *anyopaque, windows: *Windows, window_index: u32) void,
    resize: fn (iface: *anyopaque, windows: *Windows, window_index: u32, resize_value: f32, dir: window_ops.Direction) void,
    equalize: fn (iface: *anyopaque, windows: *Windows) void,
    changeFocusedWindow: fn (iface: *anyopaque, windows: *Windows, window_index: u32, dir: window_ops.Direction) void,

    pub fn init(
        impl_struct: *anyopaque,
        openWindowFn: fn (iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) Allocator.Error!*Window,
        closeWindowFn: fn (iface: *anyopaque, windows: *Windows, window_index: u32) void,
        resizeFn: fn (iface: *anyopaque, windows: *Windows, window_index: u32, resize_value: f32, dir: window_ops.Direction) void,
        equalizeFn: fn (iface: *anyopaque, windows: *Windows) void,
        changeFocusedWindowFn: fn (iface: *anyopaque, windows: *Windows, window_index: u32, dir: window_ops.Direction) void,
    ) LayoutInterface {
        return .{
            .impl_struct = impl_struct,
            .openWindow = openWindowFn,
            .closeWindow = closeWindowFn,
            .resize = resizeFn,
            .equalize = equalizeFn,
            .changeFocusedWindow = changeFocusedWindowFn,
        };
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

    pub fn closeFocusedWindow(windows: *Windows) void {
        if (windows.wins.items.len == 0) return;
        // global.resize(windows.focusedWindow());
        // global.closeWindow(windows.focusedWindow().index);
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
