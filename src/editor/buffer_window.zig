const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const math = std.math;

const imgui = @import("imgui");

const globals = @import("../core.zig").globals;
const ui = globals.ui;
const editor = globals.editor;
const Buffer = @import("../core.zig").Buffer;
const BufferHandle = @import("../core.zig").BufferHandle;
const utils = @import("../utils.zig");
const NaryTree = @import("../nary.zig").NaryTree;

pub const BufferWindowTree = NaryTree(BufferWindow);
pub const BufferWindowNode = BufferWindowTree.Node;

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn left(rect: Rect) f32 {
        return rect.x;
    }
    pub fn top(rect: Rect) f32 {
        return rect.y;
    }
    pub fn right(rect: Rect) f32 {
        return rect.x + rect.w;
    }
    pub fn bottom(rect: Rect) f32 {
        return rect.y + rect.h;
    }

    pub fn leftTop(rect: Rect) [2]f32 {
        return .{ rect.x, rect.y };
    }

    pub fn rightBottom(rect: Rect) [2]f32 {
        return .{ rect.x + rect.w, rect.y + rect.h };
    }

    pub fn fromMinMax(min: [2]f32, max: [2]f32) Rect {
        return .{
            .x = min[0],
            .y = min[1],
            .w = max[0] - min[0],
            .h = max[1] - min[1],
        };
    }
};

pub const Size = struct {
    w: f32 = 0,
    h: f32 = 0,
};

pub const BufferWindow = struct {
    pub const CursorRect = struct {
        rect: Rect,

        col: u32 = 0xFFFFFFFF,
        rounding: f32 = 0.0,
        flags: struct {
            closed: bool = false,
            round_corners_top_left: bool = false,
            round_corners_top_right: bool = false,
            round_corners_bottom_left: bool = false,
            round_corners_bottom_right: bool = false,
            round_corners_none: bool = false,
        } = .{},
        thickness: f32 = 1.0,
    };

    pub const Dir = enum {
        north,
        east,
        south,
        west,
    };

    percent_of_parent: f32 = 1,
    dir: Dir = .north,

    bhandle: BufferHandle,
    first_visiable_row: u64 = 1,
    cursor_key: u64,

    rect: Rect = .{}, // Reset every frame
    visible_lines: u64 = 0, // Set every frame

    pub fn getAndSetWindows(tree: *BufferWindowTree, allocator: std.mem.Allocator, area: Rect) ![]*BufferWindowNode {
        var root = tree.root orelse return &.{};
        var tree_array = try tree.treeToArray(allocator);

        root.data.rect = area;
        for (tree_array) |node| {
            var rect = if (node.parent) |n| n.data.rect else area;
            _ = getAndSetSize(node, rect);
        }

        return tree_array;
    }

    pub fn init(bhandle: BufferHandle, first_visiable_row: u64, dir: Dir, percent: f32, cursor_key: u64) !BufferWindow {
        try (bhandle.getBuffer().?).marks.put(cursor_key, .{});

        return .{
            .bhandle = bhandle,
            .dir = dir,
            .percent_of_parent = percent,
            .cursor_key = cursor_key,
            .first_visiable_row = first_visiable_row,
        };
    }

    pub fn deinit(buffer_window: *BufferWindow) void {
        var buffer = buffer_window.bhandle.getBuffer() orelse return;
        _ = buffer.marks.swapRemove(buffer_window.cursor_key);
    }

    pub fn cursor(buffer_window: *BufferWindow) Buffer.RowCol {
        var buffer = buffer_window.bhandle.getBuffer().?;
        return buffer.marks.get(buffer_window.cursor_key).?;
    }

    pub fn setCursor(buffer_window: *BufferWindow, new_cursor: Buffer.RowCol) void {
        var buffer = buffer_window.bhandle.getBuffer().?;
        var c = buffer.marks.getPtr(buffer_window.cursor_key).?;
        c.* = new_cursor;
    }

    pub fn setCursorCol(buffer_window: *BufferWindow, col: u64) void {
        var buffer = buffer_window.bhandle.getBuffer().?;
        var c = buffer.marks.getPtr(buffer_window.cursor_key).?;
        c.col = col;
    }

    pub fn setCursorRow(buffer_window: *BufferWindow, row: u64) void {
        var buffer = buffer_window.bhandle.getBuffer().?;
        var c = buffer.marks.getPtr(buffer_window.cursor_key).?;
        c.row = row;
    }

    pub fn lastVisibleRow(buffer_window: *BufferWindow) u64 {
        var res = buffer_window.first_visiable_row + buffer_window.visible_lines -| 1;
        const line_count = buffer_window.bhandle.getBuffer().?.lineCount();
        res = utils.bound(res, 1, line_count);
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
        var buffer = buffer_win.bhandle.getBuffer() orelse return;

        buffer_win.first_visiable_row += offset;
        buffer_win.first_visiable_row = std.math.min(
            buffer.lineCount(),
            buffer_win.first_visiable_row,
        );

        buffer_win.cursorFollowWindow();
    }

    pub fn scrollUp(buffer_win: *BufferWindow, offset: u64) void {
        buffer_win.first_visiable_row -|= offset;
        buffer_win.first_visiable_row = std.math.max(1, buffer_win.first_visiable_row);

        buffer_win.cursorFollowWindow();
    }

    pub fn cursorFollowWindow(buffer_win: *BufferWindow) void {
        var cur = buffer_win.cursor();

        if (!utils.inRange(cur.row, buffer_win.first_visiable_row, buffer_win.lastVisibleRow())) {
            const row = if (cur.row > buffer_win.lastVisibleRow()) buffer_win.lastVisibleRow() else buffer_win.first_visiable_row;
            buffer_win.setCursor(.{ .row = row, .col = cur.col });
        }
    }

    pub fn windowFollowCursor(buffer_win: *BufferWindow) void {
        const cursor_row = buffer_win.cursor().row;
        if (cursor_row <= buffer_win.first_visiable_row)
            buffer_win.first_visiable_row = cursor_row
        else if (cursor_row > buffer_win.lastVisibleRow())
            buffer_win.first_visiable_row += cursor_row - buffer_win.lastVisibleRow();
    }
};
