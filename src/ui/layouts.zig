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

    pub fn remove(layouts: *Layouts, layout_type_name: []const u8) void {
        if (layouts.layouts.items.len == 1) {
            print("Can't remove layout when only one is left\n", .{});
            return;
        }

        for (layouts.layouts.items) |layout, i| {
            if (eql(layout.type_name, layout_type_name)) {
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
