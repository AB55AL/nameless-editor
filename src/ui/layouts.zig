const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;

const globals = @import("../globals.zig");
const global = globals.global;
const internal = globals.internal;
const utils = @import("../editor/utils.zig");
const window_ops = @import("window_ops.zig");
const window = @import("window.zig");
const Window = window.Window;
const Windows = window.Windows;

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

    pub fn remove(layouts: *Layouts, index: usize) void {
        if (layouts.layouts.items.len == 1) {
            print("Can't remove layout when only one is left\n", .{});
            return;
        }

        var layout = layouts.layouts.swapRemove(index);
        internal.allocator.free(layout.type_name);
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

    openWindow: *const fn (iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) Allocator.Error!*Window,
    closeWindow: *const fn (iface: *anyopaque, windows: *Windows, window_index: u32) void,
    resize: *const fn (iface: *anyopaque, windows: *Windows, window_index: u32, resize_value: f32, dir: window_ops.Direction) void,
    equalize: *const fn (iface: *anyopaque, windows: *Windows) void,
    changeFocusedWindow: *const fn (iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) void,
    cycleThroughWindows: *const fn (iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) void,

    pub fn init(
        impl_struct: *anyopaque,
        openWindowFn: *const fn (iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) Allocator.Error!*Window,
        closeWindowFn: *const fn (iface: *anyopaque, windows: *Windows, window_index: u32) void,
        resizeFn: *const fn (iface: *anyopaque, windows: *Windows, window_index: u32, resize_value: f32, dir: window_ops.Direction) void,
        equalizeFn: *const fn (iface: *anyopaque, windows: *Windows) void,
        changeFocusedWindowFn: *const fn (iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) void,
        cycleThroughWindowsFn: *const fn (iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) void,
    ) LayoutInterface {
        return .{
            .impl_struct = impl_struct,
            .openWindow = openWindowFn,
            .closeWindow = closeWindowFn,
            .resize = resizeFn,
            .equalize = equalizeFn,
            .changeFocusedWindow = changeFocusedWindowFn,
            .cycleThroughWindows = cycleThroughWindowsFn,
        };
    }
};

pub const TileRight = struct {
    masters_num: u8,

    pub fn init(masters_num: u8) TileRight {
        return .{
            .masters_num = masters_num,
        };
    }

    pub fn interface(self: *TileRight) LayoutInterface {
        return LayoutInterface.init(
            @ptrCast(*anyopaque, self),
            TileRight.openWindow,
            TileRight.closeWindow,
            TileRight.resize,
            TileRight.equalize,
            TileRight.changeFocusedWindow,
            TileRight.cycleThroughWindows,
        );
    }

    fn openWindow(iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) Allocator.Error!*Window {
        _ = dir;
        var self = @ptrCast(*TileRight, @alignCast(@alignOf(TileRight), iface));

        var color = @mod(std.crypto.random.int(u24), 0x33_33_33);
        const w = Window{
            .index = Window.newIndex(),
            .x = 0,
            .y = 0,
            .width = 1,
            .height = 1,
            .background_color = color,
        };
        windows.focused_window_index = w.index;
        try windows.wins.append(w);
        self.arrange(windows);
        return &windows.wins.items[windows.wins.items.len - 1];
    }

    fn closeWindow(iface: *anyopaque, windows: *Windows, window_index: u32) void {
        var self = @ptrCast(*TileRight, @alignCast(@alignOf(TileRight), iface));

        var index = windows.windowArrayIndex(window_index);
        _ = windows.wins.swapRemove(index);
        self.arrange(windows);
    }

    fn resize(iface: *anyopaque, windows: *Windows, window_index: u32, resize_value: f32, dir: window_ops.Direction) void {
        _ = window_index;
        _ = dir;
        var self = @ptrCast(*TileRight, @alignCast(@alignOf(TileRight), iface));

        var masters_num = std.math.min(windows.wins.items.len, self.masters_num);
        var masters = windows.wins.items[0..masters_num];

        // Cap the resize value to make the window take up only 95% of the screen
        var master_width = masters[0].width + resize_value;
        master_width = if (master_width >= 0.95)
            0.95
        else if (master_width <= 0.05)
            0.05
        else
            master_width;

        for (masters) |*master| {
            master.width = master_width;
        }

        var stack = windows.wins.items[masters_num..];
        var win_x = master_width;
        var win_width = 1 - master_width;
        for (stack) |*win| {
            win.x = win_x;
            win.width = win_width;
        }
    }

    fn equalize(iface: *anyopaque, windows: *Windows) void {
        var self = @ptrCast(*TileRight, @alignCast(@alignOf(TileRight), iface));

        windows.wins.items[0].width = 0.5;
        self.arrange(windows);
    }

    fn changeFocusedWindow(iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) void {
        cycleThroughWindows(
            iface,
            windows,
            switch (dir) {
                .right, .below, .next => .next,
                .left, .above, .prev => .prev,
                else => return,
            },
        );
    }
    fn cycleThroughWindows(iface: *anyopaque, windows: *Windows, dir: window_ops.Direction) void {
        _ = iface;
        for (windows.wins.items) |win, i| {
            if (win.index == windows.focused_window_index) {
                const index = @intCast(i32, i);
                var next_win_index: i32 = if (dir == .next)
                    index + 1
                else
                    index - 1;
                if (next_win_index >= windows.wins.items.len) next_win_index = 0;
                if (next_win_index < 0) next_win_index = @intCast(i32, windows.wins.items.len) - 1;

                windows.focused_window_index = windows.wins.items[@intCast(u32, next_win_index)].index;
                return;
            }
        }
    }

    fn arrange(self: *TileRight, windows: *Windows) void {
        if (windows.wins.items.len == 1) {
            var win = &windows.wins.items[0];
            win.x = 0;
            win.y = 0;
            win.width = 1;
            win.height = 1;
            return;
        }

        var masters_num = std.math.min(windows.wins.items.len, self.masters_num);
        var masters = windows.wins.items[0..masters_num];

        const master_x = 0;
        const master_width = if (masters_num == windows.wins.items.len)
            1
        else if (masters[0].width == 1)
            0.5
        else
            masters[0].width;

        const master_height = 1.0 / @intToFloat(f32, masters.len);
        // arrange masters
        for (masters) |*master, index| {
            var i = @intToFloat(f32, index);
            master.x = master_x;
            master.width = master_width;
            master.y = master_height * i;
            master.height = master_height;
        }

        var stack = windows.wins.items[masters_num..];
        // arrange the stack
        const stack_x = master_width;
        const stack_width = utils.abs(master_width - 1.0);
        const stack_height = 1.0 / @intToFloat(f32, stack.len);
        for (stack) |*win, index| {
            var i = @intToFloat(f32, index);
            win.x = stack_x;
            win.width = stack_width;
            win.height = stack_height;
            win.y = stack_height * i;
        }
    }
};
