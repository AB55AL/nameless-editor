const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const globals = @import("../core.zig").globals;
const ui = globals.ui;
const editor = globals.editor;
const Buffer = @import("../core.zig").Buffer;
const math = @import("math.zig");
const utils = @import("../utils.zig");
const NaryTree = @import("../nary.zig").NaryTree;

pub const BufferWindowTree = NaryTree(BufferWindow);
pub const BufferWindowNode = BufferWindowTree.Node;

pub const BufferWindow = struct {
    pub const Rect = struct {
        x: f32 = 0,
        y: f32 = 0,
        w: f32 = 0,
        h: f32 = 0,
    };

    pub const Size = struct {
        w: f32 = 0,
        h: f32 = 0,
    };

    pub const Dir = enum {
        north,
        east,
        south,
        west,
    };

    percent_of_parent: f32 = 1,
    dir: Dir = .north,

    rect: Rect = .{}, // Reset every frame

    buffer: *Buffer,
    first_visiable_row: u64,
    visible_lines: u64 = 0, // Set every frame

    pub fn getAndSetWindows(root: *BufferWindowNode, allocator: std.mem.Allocator, area: Rect) ![]*BufferWindowNode {
        var tree_array = try root.treeToArray(allocator);

        root.data.rect = area;
        for (tree_array) |node| {
            var rect = if (node.parent) |n| n.data.rect else area;
            _ = getAndSetSize(node, rect);
        }

        return tree_array;
    }

    pub fn lastVisibleRow(buffer_window: *BufferWindow) u64 {
        var res = buffer_window.first_visiable_row + buffer_window.visible_lines -| 1;
        if (res == 0)
            res = 1
        else if (res > buffer_window.buffer.lineCount())
            res = buffer_window.buffer.lineCount();
        return res;
    }

    fn getAndSetSize(buffer_window: *BufferWindowNode, area: Rect) Rect {
        _ = area;
        if (buffer_window.first_child == null) return buffer_window.data.rect;

        var rect = &buffer_window.data.rect;
        var child = buffer_window.first_child;
        while (child) |c| {
            var child_size: Size = switch (c.data.dir) {
                .north, .south => Size{ .w = rect.w, .h = rect.h * c.data.percent_of_parent },
                .east, .west => Size{ .w = rect.w * c.data.percent_of_parent, .h = rect.h },
            };

            switch (c.data.dir) {
                .north => {
                    c.data.rect = .{
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
                    c.data.rect = .{
                        .x = rect.x + rect.w,
                        .y = rect.y,
                        .w = child_size.w,
                        .h = child_size.h,
                    };
                },
                .south => {
                    rect.h -= child_size.h;
                    c.data.rect = .{
                        .x = rect.x,
                        .y = rect.y + rect.h,
                        .w = child_size.w,
                        .h = child_size.h,
                    };
                },
                .west => {
                    c.data.rect = .{
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

    pub fn relativeBufferRowFromAbsolute(buffer_win: *BufferWindow, absolute: u64) u64 {
        if (buffer_win.first_visiable_row == 1) return absolute;
        return absolute -| buffer_win.first_visiable_row + 1;
    }

    pub fn scrollDown(buffer_win: *BufferWindow, offset: u64) void {
        buffer_win.first_visiable_row += offset;
        buffer_win.first_visiable_row = std.math.min(
            buffer_win.buffer.lineCount(),
            buffer_win.first_visiable_row,
        );

        buffer_win.resetBufferCursorToBufferWindow();
    }

    pub fn scrollUp(buffer_win: *BufferWindow, offset: u64) void {
        if (buffer_win.first_visiable_row <= offset)
            buffer_win.first_visiable_row = 1
        else
            buffer_win.first_visiable_row -= offset;

        buffer_win.first_visiable_row = std.math.max(1, buffer_win.first_visiable_row);

        buffer_win.resetBufferCursorToBufferWindow();
    }

    pub fn resetBufferCursorToBufferWindow(buffer_win: *BufferWindow) void {
        var cursor = buffer_win.buffer.getRowAndCol(buffer_win.buffer.cursor_index);

        if (!utils.inRange(cursor.row, buffer_win.first_visiable_row, buffer_win.lastVisibleRow())) {
            if (cursor.row > buffer_win.lastVisibleRow())
                buffer_win.buffer.moveAbsolute(buffer_win.lastVisibleRow(), cursor.col)
            else
                buffer_win.buffer.moveAbsolute(buffer_win.first_visiable_row, cursor.col);
        }
    }

    pub fn resetBufferWindowRowsToBufferCursor(buffer_win: *BufferWindow) void {
        var cursor_row = buffer_win.buffer.getRowAndCol(buffer_win.buffer.cursor_index).row;

        if (!utils.inRange(cursor_row, buffer_win.first_visiable_row, buffer_win.lastVisibleRow())) {
            buffer_win.first_visiable_row = cursor_row;
        }
    }
};
