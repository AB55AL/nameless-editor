const std = @import("std");
const print = std.debug.print;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

const math = @import("math.zig");
const shape2d = @import("shape2d.zig");
const Rect = shape2d.Rect;
const utils = @import("../utils.zig");
const Glyph = shape2d.Glyph;
const editor = @import("../globals.zig").editor;
const ui = @import("../globals.zig").ui;

pub const Action = struct {
    /// User clicked but is still holding the mouse button
    half_click: bool = false,
    /// User clicked and let the mouse button go AND is on the same widget that had the half click
    full_click: bool = false,
    hover: bool = false,
    drag_delta: math.Vec2(i16) = .{ .x = 0, .y = 0 },
    string_selection_range: ?(struct { start: u64, end: u64 }) = null,
};

pub const Flags = enum(u32) {
    clickable = 1,
    render_background = 2,
    draggable = 4,
    clip = 8,
    highlight_text = 16,
    text_cursor = 32,
};

pub const State = struct {
    mousex: f32 = 0,
    mousey: f32 = 0,
    mousedown: bool = false,
    hot: u32 = 0, // zero means no active item
    active: u32 = 0, // zero means no active item
    window_width: u32 = 800,
    window_height: u32 = 800,

    focused_widget: ?*Widget = null,
    first_widget_tree: ?*Widget = null,
    last_widget_tree: ?*Widget = null,

    font: shape2d.Font,
    max_id: u32 = 1,

    shape_cmds: ArrayList(shape2d.ShapeCommand),
    pass: Pass = .layout,

    pub fn deinit(state: *State, allocator: std.mem.Allocator) void {
        state.font.deinit();
        state.shape_cmds.deinit();

        var widget_tree = ui.state.first_widget_tree;
        while (widget_tree) |wt| {
            widget_tree = wt.next_sibling;
            if (wt.first_child) |fc| fc.deinitTree(allocator);
            allocator.destroy(wt);
        }
    }

    pub const Pass = enum {
        layout,
        input_and_render,
    };
};

pub const Widget = struct {
    parent: ?*Widget = null,
    first_child: ?*Widget = null,
    next_sibling: ?*Widget = null,
    last_child: ?*Widget = null,
    prev_sibling: ?*Widget = null,

    layout_of_children: Layouts,
    id: u32,

    rect: shape2d.Rect,

    drag_start: math.Vec2(i16) = .{ .x = -1, .y = -1 },
    // When dragging this value will be the same as the mouse position
    drag_end: math.Vec2(i16) = .{ .x = -2, .y = -2 },

    features_flags: u32,
    /// When ever a widget is added to the tree it is placed at the end of the children list,
    /// but when it already exists it will be placed in the list at index active_children.
    /// splitting the list into two sections of widgets, active and non-active.
    /// This indicates the number of children that called widgetStart().
    /// It is reset every frame.
    active_children: u8 = 0,

    pub fn deinitTree(widget: *Widget, allocator: std.mem.Allocator) void {
        if (widget.first_child) |fc| fc.deinitTree(allocator);
        if (widget.next_sibling) |ns| ns.deinitTree(allocator);
        allocator.destroy(widget);
    }

    pub fn lastActiveChild(parent: *Widget) *Widget {
        utils.assert(parent.active_children > 0, utils.fileLocation(@src()) ++ "active_children count must be > 0");
        return parent.getChildAt(parent.active_children - 1);
    }

    pub fn pushChild(parent: *Widget, allocator: std.mem.Allocator, child_id: u32, layout: Layouts, width: f32, height: f32, features_flags: []const Flags) !*Widget {
        if (widgetExists(child_id)) |widget| {
            if (ui.state.pass == .layout) {
                widget.rect.w = width;
                widget.rect.h = height;
                parent.layout_of_children.applyLayout(parent, widget, width, height);
                parent.repositonChild(widget);
            }
            return widget;
        }

        var flags: u32 = 0;
        for (features_flags) |f| flags |= @enumToInt(f);

        var widget = try parent.addChild(allocator, .{
            .layout_of_children = layout,
            .id = child_id,
            .rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .features_flags = flags,
        });

        parent.layout_of_children.applyLayout(parent, widget, width, height);

        parent.active_children += 1;
        return widget;
    }

    pub fn isChildOf(widget: *Widget, id: u32) bool {
        var parent = widget.parent;
        while (parent) |p| {
            if (p.id == id) {
                return true;
            } else {
                parent = p.parent;
            }
        }

        return false;
    }

    pub fn resetActiveChildrenCount(widget: *Widget) void {
        if (widget.first_child) |fc| fc.resetActiveChildrenCount();
        if (widget.next_sibling) |ns| ns.resetActiveChildrenCount();

        widget.active_children = 0;
    }

    pub fn applyOffset(widget: *Widget, offset: shape2d.Rect) void {
        if (widget.first_child) |fc| fc.applyOffset(offset);
        if (widget.next_sibling) |ns| ns.applyOffset(offset);

        widget.rect.x += offset.x;
        widget.rect.y += offset.y;
        widget.rect.w += offset.w;
        widget.rect.h += offset.h;
    }

    pub fn numOfChildren(widget: *Widget) u32 {
        var count: u32 = 0;

        var child = widget.first_child;
        while (child) |w| {
            count += 1;
            child = w.next_sibling;
        }

        return count;
    }

    pub fn numOfSiblings(widget: *Widget) u32 {
        var count: u32 = 0;

        var child = widget.next_sibling;
        while (child) |w| {
            count += 1;
            child = w.next_sibling;
        }

        return count;
    }

    pub fn lastSibling(widget: *Widget) *Widget {
        var w = widget;
        while (w.next_sibling) |ns| w = ns;
        return w;
    }

    pub fn enabled(widget: *Widget, flag: Flags) bool {
        const f = @enumToInt(flag);
        return (widget.features_flags & f == f);
    }

    pub fn walkListForward(widget: *Widget, function: *const fn (*Widget) void) void {
        var current_widget: ?*Widget = widget;
        while (current_widget) |w| {
            function(w);
            current_widget = w.next_sibling;
        }
    }

    pub fn walkListBackwords(widget: *Widget, function: *const fn (*Widget, anytype) void, args: anytype) void {
        var current_widget: ?*Widget = widget;
        while (current_widget) |w| {
            function(w, args);
            current_widget = w.prev_sibling;
        }
    }

    pub fn treeDepth(widget: *Widget, level: u32) u32 {
        var res: u32 = level;
        if (widget.first_child) |fc| {
            res = fc.treeDepth(level + 1);
        }
        if (widget.next_sibling) |ns| {
            res = std.math.max(res, ns.treeDepth(level));
        }

        return res;
    }

    pub fn capSubtreeToParentRect(widget: *Widget, level: u32) void {
        if (level == 0) {
            var current_widget: ?*Widget = widget;
            while (current_widget) |w| {
                if (widget.parent) |p| {
                    widget.rect.w = std.math.min(widget.rect.w, p.rect.w);
                    widget.rect.h = std.math.min(widget.rect.h, p.rect.h);
                }
                current_widget = w.next_sibling;
            }
        } else {
            if (widget.first_child) |fc| fc.capSubtreeToParentRect(level - 1);
            if (widget.next_sibling) |ns| ns.capSubtreeToParentRect(level);
        }
    }

    fn widgetExists(id: u32) ?*Widget {
        if (ui.state.first_widget_tree == null) return null;
        return widgetExistsRecursive(ui.state.first_widget_tree.?, id);
    }

    fn widgetExistsRecursive(widget: *Widget, wanted_id: u32) ?*Widget {
        var result: ?*Widget = null;
        if (widget.id == wanted_id) result = widget;
        if (result) |r| return r;

        if (widget.first_child) |fc| result = fc.widgetExistsRecursive(wanted_id);
        if (result) |r| return r;

        if (widget.next_sibling) |ns| result = ns.widgetExistsRecursive(wanted_id);
        if (result) |r| return r;

        return result;
    }

    fn addChild(widget: *Widget, allocator: std.mem.Allocator, new_child: Widget) !*Widget {
        var child = try allocator.create(Widget);
        child.* = new_child;
        child.parent = widget;
        child.next_sibling = null;

        if (widget.first_child == null) {
            child.prev_sibling = null;

            widget.first_child = child;
            widget.last_child = child;
        } else {
            var last_sibling = widget.last_child.?;
            child.prev_sibling = last_sibling;
            last_sibling.next_sibling = child;
            widget.last_child = child;
        }

        return child;
    }

    fn removeSubtree(widget: *Widget) *Widget {
        utils.assert(widget.parent != null, "A widget subtree must have a parent in order to remove it from the list");
        var parent = widget.parent.?;
        if (widget == parent.first_child) {
            parent.first_child = widget.next_sibling;
        } else if (widget == parent.last_child) {
            parent.last_child = widget.prev_sibling;
        }

        if (widget.prev_sibling) |ps| ps.next_sibling = widget.next_sibling;
        if (widget.next_sibling) |ns| ns.prev_sibling = widget.prev_sibling;

        widget.parent = null;
        widget.next_sibling = null;
        widget.prev_sibling = null;

        return widget;
    }

    fn insertAt(parent: *Widget, widget_to_be_inserted: *Widget, index: u32) void {
        if (index == 0) {
            if (parent.first_child) |fc| fc.prev_sibling = widget_to_be_inserted;
            widget_to_be_inserted.next_sibling = parent.first_child;
            parent.first_child = widget_to_be_inserted;
        } else if (index >= parent.numOfChildren()) {
            if (parent.last_child) |lc| lc.next_sibling = widget_to_be_inserted;
            widget_to_be_inserted.prev_sibling = parent.last_child;
            parent.last_child = widget_to_be_inserted;
        } else {
            var widget = parent.getChildAt(index);

            if (widget.prev_sibling) |ps| ps.next_sibling = widget_to_be_inserted;

            widget_to_be_inserted.prev_sibling = widget.prev_sibling;
            widget.prev_sibling = widget_to_be_inserted;
            widget_to_be_inserted.next_sibling = widget;
            widget_to_be_inserted.parent = parent;
        }

        widget_to_be_inserted.parent = parent;
    }

    fn getChildAt(parent: *Widget, index: u32) *Widget {
        var widget = parent.first_child;
        var i: u32 = 0;
        while (widget) |w| {
            if (i == index) {
                return w;
            }
            widget = w.next_sibling;
            i += 1;
        }

        return parent.first_child.?;
    }

    fn repositonChild(parent: *Widget, child: *Widget) void {
        var widget = child.removeSubtree();
        parent.insertAt(widget, parent.active_children);
        parent.active_children += 1;
    }
};

pub fn container(allocator: std.mem.Allocator, layout: Layouts, region: shape2d.Rect) !void {
    var id = newId();
    if (Widget.widgetExists(id)) |widget| {
        ui.state.focused_widget = widget;
        widget.rect.w = region.w;
        widget.rect.h = region.h;
        if (ui.state.pass == .input_and_render)
            try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, 0xFFFFFF);
        return;
    }

    var widget = try allocator.create(Widget);
    widget.* = .{
        .layout_of_children = layout,
        .id = id,
        .parent = null,
        .first_child = null,
        .next_sibling = null,
        .last_child = null,
        .prev_sibling = null,
        .rect = region,
        .features_flags = 0,
    };

    if (ui.state.first_widget_tree == null) {
        ui.state.first_widget_tree = widget;
        ui.state.last_widget_tree = null;
    } else {
        if (ui.state.last_widget_tree) |lwt| {
            lwt.next_sibling = widget;
            widget.prev_sibling = lwt;
        } else {
            ui.state.first_widget_tree.?.next_sibling = widget;
        }

        ui.state.last_widget_tree = widget;
    }

    ui.state.focused_widget = widget;
    if (ui.state.pass == .input_and_render)
        try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, 0xFFFFFF);
}

pub fn containerEnd() void {
    utils.assert(ui.state.focused_widget != null, "ui.state.focused_widget must never be null for start and end calls. Make sure to call the container function");
    ui.state.focused_widget = ui.state.focused_widget.?.parent;
}

pub fn widgetStart(args: struct {
    allocator: std.mem.Allocator,
    id: u32,
    layout: Layouts,
    w: f32,
    h: f32,
    features_flags: []const Flags,

    string: ?[]const u8 = null,
    cursor_index: u64 = 0,

    bg_color: u24 = 0,
}) !Action {
    utils.assert(ui.state.focused_widget != null, "ui.state.focused_widget must never be null for start and end calls. Make sure to call the container function");
    ui.state.focused_widget = try ui.state.focused_widget.?.pushChild(args.allocator, args.id, args.layout, args.w, args.h, args.features_flags);

    var widget = ui.state.focused_widget.?;
    var action = Action{};
    if (ui.state.pass == .layout) return action;

    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.clickable) and contains(ui.state.mousex, ui.state.mousey, widget.rect)) {
        ui.state.hot = args.id;
        action.hover = true;
        if ((ui.state.active == 0 or widget.isChildOf(ui.state.active)) and ui.state.mousedown) {
            ui.state.active = args.id;
            action.half_click = true;
        }

        if (ui.state.active == args.id and !ui.state.mousedown)
            action.full_click = true;
    }

    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.draggable)) {
        if (action.half_click) {
            widget.drag_start.x = @floatToInt(i16, ui.state.mousex);
            widget.drag_start.y = @floatToInt(i16, ui.state.mousey);

            widget.drag_end = widget.drag_start;
        } else if (ui.state.active == args.id and ui.state.mousedown) {
            widget.drag_end.x = @floatToInt(i16, ui.state.mousex);
            widget.drag_end.y = @floatToInt(i16, ui.state.mousey);

            if (!widget.drag_start.eql(widget.drag_end)) {
                action.drag_delta = widget.drag_end.sub(widget.drag_start);
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.render_background)) {
        try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, args.bg_color);
    }

    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.clip)) {
        try shape2d.ShapeCommand.pushClip(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h);
    }

    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.highlight_text) and widget.enabled(.draggable) and args.string != null) {
        var s = args.string.?;
        var line_height = ui.state.font.newLineOffset();

        const last_line_y = @floatToInt(i16, widget.rect.y + widget.rect.h - line_height + 1);
        widget.drag_end.y = utils.minOrMax(i16, widget.drag_end.y, @floatToInt(i16, widget.rect.y), last_line_y);
        widget.drag_start.y = utils.minOrMax(i16, widget.drag_start.y, @floatToInt(i16, widget.rect.y), last_line_y);

        widget.drag_end.x = utils.minOrMax(i16, widget.drag_end.x, @floatToInt(i16, widget.rect.x), @floatToInt(i16, widget.rect.x + widget.rect.w));
        widget.drag_start.x = utils.minOrMax(i16, widget.drag_start.x, @floatToInt(i16, widget.rect.x), @floatToInt(i16, widget.rect.x + widget.rect.w));

        var end_glyph = locateGlyphCoords(widget.drag_end, s, widget.rect);
        var start_glyph = if (widget.drag_start.eql(widget.drag_end)) end_glyph else locateGlyphCoords(widget.drag_start, s, widget.rect);

        if (!start_glyph.location.eql(end_glyph.location)) {
            var start_point: math.Vec2(f32) = .{ .x = 0, .y = 0 }; // the point closest to 0,0
            var end_point: math.Vec2(f32) = .{ .x = 0, .y = 0 }; // the point furthest away from 0,0

            if (start_glyph.location.y <= end_glyph.location.y) {
                start_point = .{ .x = start_glyph.location.x, .y = start_glyph.location.y };
                end_point = .{ .x = end_glyph.location.x, .y = end_glyph.location.y };
                end_point.x += end_glyph.location.w;
            } else {
                start_point = .{ .x = end_glyph.location.x, .y = end_glyph.location.y };
                end_point = .{ .x = start_glyph.location.x, .y = start_glyph.location.y };
                end_point.x += start_glyph.location.w;
            }

            var next_line_start: f32 = start_point.y + line_height;
            if (start_point.y == end_point.y) { // same line
                const width = end_point.x - start_point.x;
                try shape2d.ShapeCommand.pushRect(start_point.x, start_point.y, width, line_height, 0x00FF00);
            } else if (next_line_start == end_point.y) { // two lines
                const first_line_w = utils.abs(widget.rect.w - (start_point.x - widget.rect.x));
                try shape2d.ShapeCommand.pushRect(start_point.x, start_point.y, first_line_w, line_height, 0x00FF00);

                const second_line_w = utils.abs(widget.rect.x - end_point.x);
                try shape2d.ShapeCommand.pushRect(widget.rect.x, end_point.y, second_line_w, line_height, 0x00FF00);
            } else { // at least three lines

                const first_line_w = utils.abs(widget.rect.w - (start_point.x - widget.rect.x));
                try shape2d.ShapeCommand.pushRect(start_point.x, start_point.y, first_line_w, line_height, 0x00FF00);

                while (next_line_start < end_point.y) : (next_line_start += line_height) {
                    try shape2d.ShapeCommand.pushRect(widget.rect.x, next_line_start, widget.rect.w, line_height, 0x00FF00);
                }

                const last_line_w = utils.abs(widget.rect.x - end_point.x);
                try shape2d.ShapeCommand.pushRect(widget.rect.x, end_point.y, last_line_w, line_height, 0x00FF00);
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.text_cursor) and args.string != null) {
        var rect = locateGlyphCoordsByIndex(args.cursor_index, args.string.?, widget.rect);
        try shape2d.ShapeCommand.pushRect(rect.x, rect.y, rect.w, rect.h, 0xFF00AA);
    }

    return action;
}

pub fn widgetEnd() !void {
    utils.assert(ui.state.focused_widget != null, "ui.state.focused_widget must never be null for start and end calls. Make sure to call the container function");

    if (ui.state.pass == .input_and_render and ui.state.focused_widget.?.enabled(.clip)) {
        var parent = ui.state.focused_widget.?.parent;
        var x: f32 = 0;
        var y: f32 = 0;
        var width = @intToFloat(f32, ui.state.window_width);
        var height = @intToFloat(f32, ui.state.window_height);

        while (parent) |p| {
            if (p.enabled(.clip)) {
                x = p.rect.x;
                y = p.rect.y;
                width = p.rect.w;
                height = p.rect.h;
                break;
            }
            parent = p.parent;
        }
        try shape2d.ShapeCommand.pushClip(x, y, width, height);
    }

    ui.state.focused_widget = ui.state.focused_widget.?.parent;
}

pub fn layoutStart(allocator: std.mem.Allocator, layout: Layouts, w: f32, h: f32, color: u24) !void {
    var id = newId();

    _ = try widgetStart(.{
        .allocator = allocator,
        .id = id,
        .layout = layout,
        .w = w,
        .h = h,
        .features_flags = &.{.render_background},
        .bg_color = color,
    });
}

pub fn layoutEnd(layout: Layouts) !void {
    utils.assert(ui.state.focused_widget.?.layout_of_children.eql(layout), "When ending a layout widget the ended layout must be the same as the started layout");
    try widgetEnd();
}

pub fn button(allocator: std.mem.Allocator, layout: Layouts, w: f32, h: f32, color: u24) !bool {
    var id = newId();

    var action = try widgetStart(.{
        .allocator = allocator,
        .id = id,
        .layout = layout,
        .w = w,
        .h = h,
        .features_flags = &.{ .clickable, .render_background },
        .bg_color = color,
    });
    var widget = ui.state.focused_widget.?;

    if (ui.state.pass == .input_and_render and action.hover) {
        ui.state.hot = id;
        var colo: u24 = 0xFF0000;
        try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, colo);
    }

    try widgetEnd();
    return action.full_click;
}

pub fn text(allocator: std.mem.Allocator, string: []const u8, features_flags: []const Flags) !void {
    const dim = stringDimension(string);
    try textWithDim(allocator, string, dim, features_flags);
}

pub fn textWithDim(allocator: std.mem.Allocator, string: []const u8, cursor_index: u64, dim: math.Vec2(f32), features_flags: []const Flags, layout: Layouts, color: u24) !Action {
    var action = try textWithDimStart(allocator, string, cursor_index, dim, features_flags, layout, color);
    try widgetEnd();

    return action;
}

pub fn textWithDimStart(allocator: std.mem.Allocator, string: []const u8, cursor_index: u64, dim: math.Vec2(f32), features_flags: []const Flags, layout: Layouts, color: u24) !Action {
    const id = newId();
    var action = try widgetStart(.{
        .allocator = allocator,
        .id = id,
        .layout = layout,
        .w = dim.x,
        .h = dim.y,
        .string = string,
        .cursor_index = cursor_index,
        .features_flags = features_flags,
        .bg_color = color,
    });

    var widget = ui.state.focused_widget.?;
    if (ui.state.pass == .input_and_render)
        try shape2d.ShapeCommand.pushText(widget.rect.x, widget.rect.y, 0xFFFFFF, string);

    return action;
}

pub fn textWithDimEnd() !void {
    try widgetEnd();
}

pub fn buttonText(allocator: std.mem.Allocator, layout: Layouts, layout_hints: Layouts, string: []const u8, color: u24) !bool {
    var id = newId();
    var dim = stringDimension(string);
    var action = try widgetStart(.{
        .allocator = allocator,
        .id = id,
        .layout = layout,
        .layout_hints = layout_hints,
        .w = dim.x,
        .h = dim.y,
        .string = string,
        .features_flags = &.{.clickable},
        .bg_color = color,
    });

    if (action.hover) {
        var widget = ui.state.focused_widget.?;
        ui.state.hot = id;
        try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, color);
    }
    _ = try textWithDim(allocator, string, 0, dim, &.{}, color);

    try widgetEnd();
    return action.full_click;
}

fn contains(x: f32, y: f32, rect: shape2d.Rect) bool {
    if (x < rect.x or
        y < rect.y or
        x >= rect.x + rect.w or
        y >= rect.y + rect.h)
        return false;

    return true;
}

pub fn stringDimension(string: []const u8) math.Vec2(f32) {
    var max_dim: math.Vec2(f32) = .{
        .x = 0,
        .y = ui.state.font.newLineOffset(),
    };

    var width_per_line: f32 = 0;
    for (string) |char| {
        var g = ui.state.font.glyphs.get(char) orelse continue;
        width_per_line += @intToFloat(f32, g.advance);

        if (char == '\n') {
            max_dim.x = std.math.max(max_dim.x, width_per_line);
            width_per_line = 0;
            max_dim.y += ui.state.font.newLineOffset();
        }
    }

    max_dim.x = std.math.max(max_dim.x, width_per_line);

    return max_dim;
}

// TODO: have a better way of generating ids
pub fn newId() u32 {
    var old_id = ui.state.max_id;
    ui.state.max_id += 1;
    return old_id;
}

pub fn beginUI() void {
    ui.state.hot = 0;
}

pub fn endUI() void {
    utils.assert(ui.state.focused_widget == null, "At the end of the UI loop the focused_widget must be null");

    if (!ui.state.mousedown) {
        ui.state.active = 0;
    }

    ui.state.max_id = 1;

    var widget_tree = ui.state.first_widget_tree;
    while (widget_tree) |wt| {
        wt.resetActiveChildrenCount();
        widget_tree = wt.next_sibling;
    }
}

/// This function assumes the string is present in the provided region
pub fn locateGlyphCoords(pos: math.Vec2(i16), string: []const u8, region: shape2d.Rect) struct { index: ?u64, location: shape2d.Rect } {
    var x = region.x;
    var y = region.y;

    var previous_line_end: math.Vec2(f32) = .{ .x = 0, .y = 0 };
    for (string) |char, i| {
        var g = ui.state.font.glyphs.get(char) orelse continue;
        var g_advance = @intToFloat(f32, g.advance);

        if (contains( // found the glyph
            @intToFloat(f32, pos.x),
            @intToFloat(f32, pos.y),
            .{ .x = x, .y = y, .w = g_advance, .h = ui.state.font.newLineOffset() },
        )) {
            return .{
                .index = i,
                .location = .{
                    .x = x,
                    .y = y,
                    .w = g_advance,
                    .h = ui.state.font.newLineOffset(),
                },
            };
        } else {
            x += g_advance;
        }

        if (char == '\n') { // end of line with a newline char
            previous_line_end = .{
                .x = x,
                .y = y,
            };

            if (utils.inRange(f32, @intToFloat(f32, pos.y), y, y + ui.state.font.newLineOffset()) or
                i == string.len - 1)
            {
                return .{
                    .index = i,
                    .location = .{
                        .x = previous_line_end.x - g_advance,
                        .y = previous_line_end.y,
                        .w = g_advance,
                        .h = ui.state.font.newLineOffset(),
                    },
                };
            }

            y += ui.state.font.newLineOffset();
            x = region.x;
        } else if (i == string.len - 1) { // end of line without a newline char
            return .{
                .index = i,
                .location = .{
                    .x = x - g_advance,
                    .y = y,
                    .w = g_advance,
                    .h = ui.state.font.newLineOffset(),
                },
            };
        }
    }

    return .{
        .index = null,
        .location = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    };
}

/// This function assumes the string is present in the provided region
pub fn locateGlyphCoordsByIndex(index: u64, string: []const u8, region: shape2d.Rect) shape2d.Rect {
    utils.assert(index < string.len, utils.fileLocation(@src()) ++ "Index must be < to string.len");

    var x = region.x;
    var y = region.y;

    for (string) |char, i| {
        var g = ui.state.font.glyphs.get(char) orelse continue;
        var g_advance = @intToFloat(f32, g.advance);
        if (i == index) {
            return .{
                .x = x,
                .y = y,
                .w = g_advance,
                .h = ui.state.font.newLineOffset(),
            };
        } else {
            x += g_advance;

            if (char == '\n') {
                x = region.x;
                y += ui.state.font.newLineOffset();
            }
        }
    }

    unreachable;
}

////////////////////////////////////////////////////////////////////////////////
//                                   Layouts
////////////////////////////////////////////////////////////////////////////////

pub const Layouts = union(enum) {
    column: Column,
    row: Row,
    grid2x2: Grid2x2,
    dynamic_row: DynamicRow,
    dynamic_column: DynamicColumn,

    pub fn applyLayout(layout: Layouts, parent: *Widget, child: *Widget, width: f32, height: f32) void {
        switch (layout) {
            inline else => |lo| @TypeOf(lo).applyLayout(parent, child, width, height),
        }
    }

    pub fn eql(layout_1: Layouts, layout_2: Layouts) bool {
        return std.meta.eql(layout_1, layout_2);
    }
};

pub const Column = struct {
    pub fn getLayout() Layouts {
        return .{ .column = Column{} };
    }

    pub fn applyLayout(parent: *Widget, child: *Widget, width: f32, height: f32) void {
        if (parent.first_child == null or parent.active_children == 0) {
            child.rect = .{
                .x = parent.rect.x,
                .y = parent.rect.y,
                .w = width,
                .h = height,
            };

            return;
        }

        var lc = parent.lastActiveChild();
        var x = lc.rect.x + lc.rect.w;
        const y = parent.rect.y;

        var widget = lc.prev_sibling;
        while (widget) |w| {
            x += w.rect.right();
            widget = w.prev_sibling;
        }

        child.rect = .{
            .x = x,
            .y = y,
            .w = width,
            .h = height,
        };
    }
};

pub const Row = struct {
    pub fn getLayout() Layouts {
        return .{ .row = Row{} };
    }

    pub fn applyLayout(parent: *Widget, child: *Widget, width: f32, height: f32) void {
        if (parent.first_child == null or parent.active_children == 0) {
            child.rect = .{
                .x = parent.rect.x,
                .y = parent.rect.y,
                .w = width,
                .h = height,
            };

            return;
        }
        var lc = parent.lastActiveChild();
        var x = lc.rect.x;

        var y = parent.rect.y + lc.rect.h;

        var widget = lc.prev_sibling;
        while (widget) |w| {
            y += w.rect.h;
            widget = w.prev_sibling;
        }

        child.rect = .{
            .x = x,
            .y = y,
            .w = width,
            .h = height,
        };
    }
};

pub const DynamicRow = struct {
    pub fn getLayout() Layouts {
        return .{ .dynamic_row = DynamicRow{} };
    }

    pub fn applyLayout(parent: *Widget, child: *Widget, width: f32, height: f32) void {
        if (parent.first_child == null or parent.active_children == 0) {
            child.rect = .{
                .x = parent.rect.x,
                .y = parent.rect.y,
                .w = width,
                .h = height,
            };

            return;
        }
        var lc = parent.lastActiveChild();
        if (!contains(lc.rect.x, lc.rect.bottom() + height, parent.rect)) {
            // must offset all previous children
            var sibling_count = @intToFloat(f32, parent.active_children);
            var offset_height = -(height / sibling_count);
            const functions = struct {
                fn func(widget: *Widget, args: anytype) void {
                    if (widget.rect.y != widget.parent.?.rect.y)
                        widget.rect.y += args.@"0";
                    widget.rect.h += args.@"0";
                }
            };
            lc.walkListBackwords(functions.func, .{offset_height});
            const depth = parent.treeDepth(0);
            var i: u32 = 0;
            while (i <= depth) : (i += 1)
                parent.capSubtreeToParentRect(i);
        }

        var x = lc.rect.x;

        var y = parent.rect.y + lc.rect.h;

        var widget = lc.prev_sibling;
        while (widget) |w| {
            y += w.rect.h;
            widget = w.prev_sibling;
        }

        child.rect = .{
            .x = x,
            .y = y,
            .w = width,
            .h = height,
        };
    }
};

pub const DynamicColumn = struct {
    pub fn getLayout() Layouts {
        return .{ .dynamic_column = DynamicColumn{} };
    }

    pub fn applyLayout(parent: *Widget, child: *Widget, width: f32, height: f32) void {
        if (parent.first_child == null or parent.active_children == 0) {
            child.rect = .{
                .x = parent.rect.x,
                .y = parent.rect.y,
                .w = width,
                .h = height,
            };

            return;
        }
        var lc = parent.lastActiveChild();
        if (!contains(lc.rect.right() + width, lc.rect.y, parent.rect)) {
            // must offset all previous children
            var sibling_count = @intToFloat(f32, parent.active_children);
            var offset_width = -(width / sibling_count);
            const functions = struct {
                fn func(widget: *Widget, args: anytype) void {
                    if (widget.rect.x != widget.parent.?.rect.x)
                        widget.rect.x += args.@"0";
                    widget.rect.w += args.@"0";
                }
            };
            lc.walkListBackwords(functions.func, .{offset_width});
            const depth = parent.treeDepth(0);
            var i: u32 = 0;
            while (i <= depth) : (i += 1)
                parent.capSubtreeToParentRect(i);
        }

        var x = lc.rect.x + lc.rect.w;
        const y = parent.rect.y;

        var widget = lc.prev_sibling;
        while (widget) |w| {
            x += w.rect.right();
            widget = w.prev_sibling;
        }

        child.rect = .{
            .x = x,
            .y = y,
            .w = width,
            .h = height,
        };
    }
};

pub const Grid2x2 = struct {
    pub fn getLayout() Layouts {
        return .{
            .grid2x2 = Grid2x2{},
        };
    }

    pub fn applyLayout(parent: *Widget, child: *Widget, width: f32, height: f32) void {
        _ = width;
        _ = height;

        switch (parent.active_children) {
            0 => {
                child.rect = parent.rect;
            },
            1 => {
                var first_child = parent.lastActiveChild();
                first_child.rect.w /= 2;

                child.rect = .{
                    .x = parent.rect.x + first_child.rect.w,
                    .y = parent.rect.y,
                    .w = first_child.rect.w,
                    .h = first_child.rect.h,
                };
            },
            2 => {
                var first_child = parent.first_child.?;
                first_child.rect.h /= 2;
                child.rect = .{
                    .x = first_child.rect.x,
                    .y = first_child.rect.y + first_child.rect.h,
                    .w = first_child.rect.w,
                    .h = first_child.rect.h,
                };
            },
            3 => {
                var second_child = parent.first_child.?.next_sibling.?;
                second_child.rect.h /= 2;
                child.rect = .{
                    .x = second_child.rect.x,
                    .y = second_child.rect.y + second_child.rect.h,
                    .w = second_child.rect.w,
                    .h = second_child.rect.h,
                };
            },
            else => unreachable,
        }
    }
};
