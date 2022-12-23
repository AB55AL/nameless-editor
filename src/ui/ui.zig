const std = @import("std");
const print = std.debug.print;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

const math = @import("math.zig");
const shape2d = @import("shape2d.zig");
const utils = @import("../utils.zig");
const Glyph = shape2d.Glyph;
const editor = @import("../globals.zig").editor;
const ui = @import("../globals.zig").ui;

pub var focused_widget: ?*Widget = null;

pub const LayoutType = enum {
    column_wise,
    row_wise,
};

pub const Action = struct {
    /// User clicked but is still holding the mouse button
    half_click: bool = false,
    /// User clicked and let the mouse button go AND is on the same widget that had the half click
    full_click: bool = false,
    hover: bool = false,
    drag_delta: math.Vec2(i16) = .{ .x = 0, .y = 0 },
};

pub const Flags = enum(u32) {
    clickable = 1,
    render_background = 2,
    draggable = 4,
    clip = 8,
    highlight_text = 16,
};

pub const State = struct {
    mousex: f32 = 0,
    mousey: f32 = 0,
    mousedown: bool = false,
    hot: u32 = 0, // zero means no active item
    active: u32 = 0, // zero means no active item
    window_width: u32 = 800,
    window_height: u32 = 800,

    first_widget_tree: ?*Widget = null,
    last_widget_tree: ?*Widget = null,

    font: shape2d.Font,
    max_id: u32 = 1,

    shape_cmds: ArrayList(shape2d.ShapeCommand),

    pub fn deinit(state: *State, allocator: std.mem.Allocator) void {
        state.font.deinit();
        state.shape_cmds.deinit();

        if (state.first_widget_tree != state.last_widget_tree) {
            var widget_tree = ui.state.first_widget_tree;
            while (widget_tree) |wt| {
                wt.deinitTree(allocator);
                widget_tree = wt.next_sibling;
            }
        } else {
            state.first_widget_tree.?.deinitTree(allocator);
        }
    }
};

pub const Widget = struct {
    parent: ?*Widget = null,
    first_child: ?*Widget = null,
    next_sibling: ?*Widget = null,
    last_child: ?*Widget = null,
    prev_sibling: ?*Widget = null,

    id: u32,

    rect: shape2d.Rect,

    drag_start: math.Vec2(i16) = .{ .x = -1, .y = -1 },
    // When dragging this value will be the same as the mouse position
    drag_end: math.Vec2(i16) = .{ .x = -2, .y = -2 },

    features_flags: u32,

    pub fn deinitTree(widget: *Widget, allocator: std.mem.Allocator) void {
        if (widget.first_child) |fc| fc.deinitTree(allocator);
        if (widget.next_sibling) |ns| ns.deinitTree(allocator);
        allocator.destroy(widget);
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

    pub fn pushChild(parent: *Widget, allocator: std.mem.Allocator, child_id: u32, layout_type: LayoutType, width: f32, height: f32, features_flags: []const Flags) !*Widget {
        if (widgetExists(child_id)) |widget| {
            return widget;
        }

        const new_pos: math.Vec2(f32) = blk: {
            if (parent.first_child == null) {
                break :blk .{
                    .x = parent.rect.x,
                    .y = parent.rect.y,
                };
            }

            var lc = parent.last_child.?;
            switch (layout_type) {
                .column_wise => {
                    var x = lc.rect.x + lc.rect.w;
                    const y = parent.rect.y;

                    var widget = lc.prev_sibling;
                    while (widget) |w| {
                        if (w.rect.x == lc.rect.x) {
                            x = std.math.max(x, w.rect.x + w.rect.w);
                        } else break;
                        widget = w.prev_sibling;
                    }

                    break :blk .{
                        .x = x,
                        .y = y,
                    };
                },
                .row_wise => {
                    var x = lc.rect.x;

                    var y = parent.rect.y + lc.rect.h;

                    var widget = lc.prev_sibling;
                    while (widget) |w| {
                        if (w.rect.x == lc.rect.x) y += w.rect.h;
                        widget = w.prev_sibling;
                    }

                    break :blk .{
                        .x = x,
                        .y = y,
                    };
                },
            }
        };

        var flags: u32 = 0;
        for (features_flags) |f| flags |= @enumToInt(f);

        return parent.addChild(allocator, .{
            .id = child_id,
            .rect = .{ .x = new_pos.x, .y = new_pos.y, .w = width, .h = height },
            .features_flags = flags,
        });
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

    pub fn lastSibling(widget: *Widget) *Widget {
        var w = widget;
        while (w.next_sibling) |ns| w = ns;
        return w;
    }

    pub fn enabled(widget: *Widget, flag: Flags) bool {
        const f = @enumToInt(flag);
        return (widget.features_flags & f == f);
    }
};

pub fn container(allocator: std.mem.Allocator, region: shape2d.Rect) !void {
    var id = newId();
    if (Widget.widgetExists(id)) |widget| {
        focused_widget = widget;
        try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, 0xFFFFFF);
        return;
    }

    var widget = try allocator.create(Widget);
    widget.* = .{
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
        ui.state.last_widget_tree = widget;
    } else {
        ui.state.last_widget_tree.?.next_sibling = widget;
        widget.prev_sibling = ui.state.last_widget_tree;

        ui.state.last_widget_tree = widget;
    }

    focused_widget = widget;
    try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, 0xFFFFFF);
}

pub fn widgetStart(allocator: std.mem.Allocator, id: u32, layout_type: LayoutType, w: f32, h: f32, string: ?[]const u8, features_flags: []const Flags) !Action {
    utils.assert(focused_widget != null, "focused_widget must never be null for start and end calls. Make sure to call the container function");
    focused_widget = try focused_widget.?.pushChild(allocator, id, layout_type, w, h, features_flags);

    var widget = focused_widget.?;
    var action = Action{};

    if (widget.enabled(.clickable) and contains(ui.state.mousex, ui.state.mousey, widget.rect)) {
        ui.state.hot = id;
        action.hover = true;
        if ((ui.state.active == 0 or widget.isChildOf(ui.state.active)) and ui.state.mousedown) {
            ui.state.active = id;
            action.half_click = true;
        }

        if (ui.state.active == id and !ui.state.mousedown)
            action.full_click = true;
    }

    if (widget.enabled(.render_background)) {
        try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, 0x0);
    }
    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.draggable)) {
        if (action.half_click) {
            widget.drag_start.x = @floatToInt(i16, ui.state.mousex);
            widget.drag_start.y = @floatToInt(i16, ui.state.mousey);

            widget.drag_end = widget.drag_start;
        } else if (ui.state.active == id and ui.state.mousedown) {
            widget.drag_end.x = @floatToInt(i16, ui.state.mousex);
            widget.drag_end.y = @floatToInt(i16, ui.state.mousey);

            if (!widget.drag_start.eql(widget.drag_end)) {
                action.drag_delta = widget.drag_end.sub(widget.drag_start);
            }
        }
    }
    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.clip)) {
        try shape2d.ShapeCommand.pushClip(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h);
    }
    ////////////////////////////////////////////////////////////////////////////
    if (widget.enabled(.highlight_text) and widget.enabled(.draggable) and string != null) {
        var s = string.?;
        var line_height = ui.state.font.newLineOffset();

        const last_line_y = @floatToInt(i16, widget.rect.y + widget.rect.h - line_height + 1);
        widget.drag_end.y = utils.minOrMax(i16, widget.drag_end.y, @floatToInt(i16, widget.rect.y), last_line_y);
        widget.drag_start.y = utils.minOrMax(i16, widget.drag_start.y, @floatToInt(i16, widget.rect.y), last_line_y);

        widget.drag_end.x = utils.minOrMax(i16, widget.drag_end.x, @floatToInt(i16, widget.rect.x), @floatToInt(i16, widget.rect.x + widget.rect.w));
        widget.drag_start.x = utils.minOrMax(i16, widget.drag_start.x, @floatToInt(i16, widget.rect.x), @floatToInt(i16, widget.rect.x + widget.rect.w));

        var start_glyph = locateGlyphCoords(widget.drag_start, s, widget.rect);
        var end_glyph = locateGlyphCoords(widget.drag_end, s, widget.rect);

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

        // cursor
        try shape2d.ShapeCommand.pushRect(end_glyph.location.x, end_glyph.location.y, end_glyph.location.w, line_height, 0xFF0000);
    }

    return action;
}

pub fn widgetEnd() !void {
    utils.assert(focused_widget != null, "focused_widget must never be null for start and end calls. Make sure to call the container function");

    if (focused_widget.?.enabled(.clip)) {
        try shape2d.ShapeCommand.pushClip(0, 0, @intToFloat(f32, ui.state.window_width), @intToFloat(f32, ui.state.window_height));
    }

    focused_widget = focused_widget.?.parent;
}

pub fn button(allocator: std.mem.Allocator, layout_type: LayoutType, w: f32, h: f32) !bool {
    var id = newId();

    var action = try widgetStart(allocator, id, layout_type, w, h, null, &.{ .clickable, .render_background });
    var widget = focused_widget.?;

    if (action.hover) {
        ui.state.hot = id;
        var color: u24 = 0xFF0000;
        try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, color);
    }

    try widgetEnd();
    return action.full_click;
}

pub fn text(allocator: std.mem.Allocator, string: []const u8, features_flags: []const Flags) !void {
    const dim = stringDimension(string);
    try textWithDim(allocator, string, dim, features_flags);
}

pub fn textWithDim(allocator: std.mem.Allocator, string: []const u8, dim: math.Vec2(f32), features_flags: []const Flags) !void {
    const id = newId();
    var action = try widgetStart(allocator, id, .column_wise, dim.x, dim.y, string, features_flags);
    _ = action;

    var widget = focused_widget.?;
    try shape2d.ShapeCommand.pushText(widget.rect.x, widget.rect.y, 0x0, string);

    try widgetEnd();
}

pub fn buttonText(allocator: std.mem.Allocator, layout_type: LayoutType, string: []const u8) !bool {
    var id = newId();
    var dim = stringDimension(string);
    var action = try widgetStart(allocator, id, layout_type, dim.x, dim.y, string, &.{.clickable});

    if (action.hover) {
        var widget = focused_widget.?;
        ui.state.hot = id;
        var color: u24 = 0x0000FF;
        try shape2d.ShapeCommand.pushRect(widget.rect.x, widget.rect.y, widget.rect.w, widget.rect.h, color);
    }
    try textWithDim(allocator, string, dim, &.{});

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

// TODO: get have a better way of generating ids
pub fn newId() u32 {
    var old_id = ui.state.max_id;
    ui.state.max_id += 1;
    return old_id;
}

pub fn begin() void {
    ui.state.hot = 0;
}

pub fn end() void {
    if (!ui.state.mousedown) {
        ui.state.active = 0;
    }

    ui.state.max_id = 1;
}

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
