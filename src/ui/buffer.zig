const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const gui = @import("gui");

const globals = @import("../core.zig").globals;
const ui = globals.ui;
const editor = globals.editor;
const Buffer = @import("../core.zig").Buffer;
const math = @import("math.zig");
const utils = @import("../utils.zig");

pub const BufferWindow = struct {
    pub const Dir = enum {
        north,
        east,
        south,
        west,
    };

    parent: ?*BufferWindow = null,
    next_sibling: ?*BufferWindow = null,
    first_child: ?*BufferWindow = null,

    percent_of_parent: f32 = 1,
    dir: Dir = .north,

    // Reset every frame
    rect: gui.Rect = .{},

    buffer: *Buffer,
    first_visiable_row: u64,

    pub fn addChild(buffer_window: *BufferWindow, allocator: std.mem.Allocator, buffer: *Buffer, first_visiable_row: u64, percent: f32, dir: Dir) !*BufferWindow {
        var new_window = try create(allocator, buffer, first_visiable_row, percent, dir);
        new_window.parent = buffer_window;

        if (buffer_window.first_child) |fc| {
            var ls = fc.lastSibling();
            ls.next_sibling = new_window;
        } else {
            buffer_window.first_child = new_window;
        }

        return new_window;
    }

    pub fn deinitTree(buffer_window: *BufferWindow, allocator: std.mem.Allocator) void {
        if (buffer_window.first_child) |fc| fc.deinitTree(allocator);
        if (buffer_window.next_sibling) |ns| ns.deinitTree(allocator);

        allocator.destroy(buffer_window);
    }

    pub fn remove(buffer_window: *BufferWindow) void {
        if (buffer_window.parent) |parent| {
            if (buffer_window == parent.first_child)
                parent.first_child = buffer_window.next_sibling;
        }

        var pre_sib = buffer_window.previousSibling() orelse return;
        pre_sib.next_sibling = buffer_window.next_sibling;
    }

    pub fn previousSibling(buffer_window: *BufferWindow) ?*BufferWindow {
        var parent = buffer_window.parent orelse return null;
        if (buffer_window == parent.first_child) return null;

        var sibling = parent.first_child;
        while (sibling) |sib| {
            if (sib.next_sibling == buffer_window)
                return sib;
        }

        return null;
    }

    pub fn lastSibling(buffer_window: *BufferWindow) *BufferWindow {
        var window = buffer_window;
        while (window.next_sibling) |ns| {
            window = ns;
        } else return window;
    }

    pub fn create(allocator: std.mem.Allocator, buffer: *Buffer, first_visiable_row: u64, percent: f32, dir: Dir) !*BufferWindow {
        var bw = try allocator.create(BufferWindow);
        bw.* = .{
            .buffer = buffer,
            .first_visiable_row = first_visiable_row,
            .percent_of_parent = percent,
            .dir = dir,
        };

        return bw;
    }

    pub fn getAndSetWindows(root: *BufferWindow, allocator: std.mem.Allocator, area: gui.Rect) ![]*BufferWindow {
        var tree_array = try root.treeToArray(allocator);

        root.rect = area;
        for (tree_array) |window| {
            var rect = if (window.parent) |p| p.rect else area;
            _ = window.getAndSetSize(rect);
        }

        return tree_array;
    }

    fn getAndSetSize(buffer_window: *BufferWindow, area: gui.Rect) gui.Rect {
        _ = area;
        if (buffer_window.first_child == null) return buffer_window.rect;

        var rect = &buffer_window.rect;
        var child = buffer_window.first_child;
        while (child) |c| {
            var child_size: gui.Size = switch (c.dir) {
                .north, .south => gui.Size{ .w = rect.w, .h = rect.h * c.percent_of_parent },
                .east, .west => gui.Size{ .w = rect.w * c.percent_of_parent, .h = rect.h },
            };

            switch (c.dir) {
                .north => {
                    c.rect = .{
                        .x = rect.x,
                        .y = rect.y,
                        .w = child_size.w,
                        .h = child_size.h,
                    };

                    rect.y += child_size.h;
                    rect.h -= child_size.h;
                },
                .east => {
                    rect.w -= child_size.w;
                    c.rect = .{
                        .x = rect.x + rect.w,
                        .y = rect.y,
                        .w = child_size.w,
                        .h = child_size.h,
                    };
                },
                .south => {
                    rect.h -= child_size.h;
                    c.rect = .{
                        .x = rect.x,
                        .y = rect.y + rect.h,
                        .w = child_size.w,
                        .h = child_size.h,
                    };
                },
                .west => {
                    c.rect = .{
                        .x = rect.x,
                        .y = rect.y,
                        .w = child_size.w,
                        .h = child_size.h,
                    };

                    rect.x += child_size.w;
                    rect.w -= child_size.w;
                },
            }

            child = c.next_sibling;
        }

        return rect.*;
    }

    pub fn treeToArray(root: *BufferWindow, allocator: std.mem.Allocator) ![]*BufferWindow {
        var array_list = ArrayList(*BufferWindow).init(allocator);
        const depth = root.treeDepth(0);
        var level: u32 = 0;
        while (level <= depth) : (level += 1) {
            try treeToArrayRecursive(root, level, &array_list);
        }

        return try array_list.toOwnedSlice();
    }

    fn treeToArrayRecursive(buffer_window: *BufferWindow, level: u32, array_list: *ArrayList(*BufferWindow)) std.mem.Allocator.Error!void {
        if (level == 0) {
            var current_window: ?*BufferWindow = buffer_window;
            while (current_window) |p| {
                try array_list.append(p);
                current_window = p.next_sibling;
            }
        } else {
            if (buffer_window.first_child) |fc| try fc.treeToArrayRecursive(level - 1, array_list);
            if (buffer_window.next_sibling) |ns| try ns.treeToArrayRecursive(level, array_list);
        }
    }

    fn treeDepth(buffer_window: *BufferWindow, level: u32) u32 {
        var res: u32 = level;
        if (buffer_window.first_child) |fc| {
            res = fc.treeDepth(level + 1);
        }
        if (buffer_window.next_sibling) |ns| {
            var second_res = ns.treeDepth(level);
            if (second_res > res) res = second_res;
        }

        return res;
    }

    pub fn absoluteBufferIndexFromRelative(buffer_win: *BufferWindow, relative: u64) u64 {
        if (buffer_win.first_visiable_row == 1) return relative;

        const offset: u64 = buffer_win.buffer.indexOfFirstByteAtRow(buffer_win.first_visiable_row);
        utils.assert(relative +| offset <= buffer_win.buffer.lines.size, "You may have passed an absolute index into this function");
        return relative +| offset;
    }

    pub fn relativeBufferIndexFromAbsolute(buffer_win: *BufferWindow, absolute: u64) u64 {
        if (buffer_win.first_visiable_row == 1) return absolute;

        const offset: u64 = buffer_win.buffer.indexOfFirstByteAtRow(buffer_win.first_visiable_row);
        return absolute -| offset;
    }

    pub fn scrollDown(buffer_win: *BufferWindow, offset: u64) void {
        buffer_win.first_visiable_row += offset;
        buffer_win.first_visiable_row = std.math.min(
            buffer_win.buffer.lines.newlines_count,
            buffer_win.first_visiable_row,
        );
    }

    pub fn scrollUp(buffer_win: *BufferWindow, offset: u64) void {
        if (buffer_win.first_visiable_row <= offset)
            buffer_win.first_visiable_row = 1
        else
            buffer_win.first_visiable_row -= offset;
    }
};

pub fn nextBufferWindow() void {
    if (&(ui.visiable_buffers[0] orelse return) == ui.focused_buffer_window) {
        ui.focused_buffer_window = &(ui.visiable_buffers[1] orelse return);
    } else {
        ui.focused_buffer_window = &(ui.visiable_buffers[0] orelse return);
    }
}
