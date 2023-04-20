const std = @import("std");
const print = std.debug.print;
const math = std.math;
const unicode = std.unicode;

const input_layer = @import("input_layer");
const imgui = @import("imgui");
const glfw = @import("glfw");

const core = @import("core");
const utils = core.utils;

const Buffer = core.Buffer;
const BufferIterator = core.Buffer.BufferIterator;
const LineIterator = core.Buffer.LineIterator;

const max_visible_rows: u64 = 4000;
const max_visible_cols: u64 = 4000;
const max_visible_bytes = max_visible_cols * 4; // multiply by 4 because a UTF-8 sequence can be 4 bytes long

pub fn tmpString(comptime fmt: []const u8, args: anytype) [:0]u8 {
    const static = struct {
        var buf: [10_000:0]u8 = undefined;
    };
    var slice = std.fmt.bufPrintZ(&static.buf, fmt, args) catch unreachable;
    static.buf[slice.len] = 0;

    return &static.buf;
}

pub fn buffers(allocator: std.mem.Allocator) !bool {
    defer imgui.end();
    if (!imgui.begin("buffers", .{ .flags = .{
        .no_nav_focus = true,
        .no_resize = false,
        .no_scroll_with_mouse = true,
        .no_scrollbar = true,
    } })) return false;

    var bw_tree = core.globals.ui.visiable_buffers_tree.root orelse {
        core.command_line.open();
        return false;
    };

    var window_focused = false;

    var size = imgui.getWindowSize();
    var rect = core.BufferWindow.Rect{ .w = size[0], .h = size[1] };
    var windows = try core.BufferWindow.getAndSetWindows(bw_tree, allocator, rect);
    defer allocator.free(windows);
    for (windows) |bw| {
        imgui.pushItemWidth(500);
        imgui.setCursorPos(.{ bw.data.rect.x, bw.data.rect.y });
        const buffer_focused = bufferWidget(bw, true, bw.data.rect.w, bw.data.rect.h);
        window_focused = window_focused or buffer_focused;
    }

    return imgui.isWindowFocused(.{}) or window_focused;
}

pub fn bufferWidget(buffer_window_node: *core.BufferWindowNode, new_line: bool, width: f32, height: f32) bool {
    const static = struct {
        pub var buf: [max_visible_bytes]u8 = undefined;
    };

    var buffer_window = &buffer_window_node.data;
    var dl = imgui.getWindowDrawList();
    dl.pushClipRect(.{
        .pmin = .{ buffer_window.rect.x, buffer_window.rect.y },
        .pmax = .{ buffer_window.rect.x + width, buffer_window.rect.y + height },
    });

    _ = imgui.beginChild(tmpString("buffer_window ({x})", .{@ptrToInt(buffer_window)}), .{
        .w = width,
        .h = height,
        .border = true,
        .flags = .{ .no_scroll_with_mouse = true, .no_scrollbar = true },
    });
    defer imgui.endChild();

    const begin_cursor_pos = imgui.getCursorPos();

    if (new_line) imgui.newLine();

    var line_h = imgui.getTextLineHeightWithSpacing();
    buffer_window.visible_lines = @floatToInt(u32, std.math.floor(height / line_h));
    buffer_window.resetBufferWindowRowsToBufferCursor();

    var buffer = buffer_window.buffer;

    const cursor_index = buffer.getIndex(buffer_window.cursor);

    // render selection
    const selection = buffer.selection.get(buffer_window.cursor);
    if (buffer.selection.selected() and utils.inRange(selection.start.row, buffer_window.first_visiable_row, buffer_window.lastVisibleRow()) and !std.meta.eql(buffer.selection.anchor, buffer_window.cursor)) {
        const start = selection.start;
        const end = selection.end;

        const selected_rows = std.math.min(max_visible_rows, (selection.end.row - selection.start.row + 1));
        var selection_rows_width: [max_visible_rows]f32 = .{0} ** max_visible_rows;
        var selection_rows_offset: [max_visible_rows]f32 = .{0} ** max_visible_rows;

        switch (buffer.selection.kind) { // get selection_rows_width
            .line, .block => {
                for (start.row..end.row + 1, 0..) |row, i| {
                    if (buffer.selection.kind == .block and buffer.countCodePointsAtRow(row) < start.col) continue;
                    selection_rows_width[i] += textLineSize(buffer, row, start.col, end.col)[0];
                }
            },
            .regular => {
                if (selected_rows == 1) {
                    selection_rows_width[0] = textLineSize(buffer, start.row, start.col, end.col)[0];
                } else if (selected_rows == 2) {
                    selection_rows_width[0] = textLineSize(buffer, start.row, start.col, Buffer.RowCol.last_col)[0];
                    selection_rows_width[1] = textLineSize(buffer, end.row, 1, end.col)[0];
                } else {
                    selection_rows_width[0] = textLineSize(buffer, start.row, start.col, Buffer.RowCol.last_col)[0];
                    for (start.row + 1..end.row, 1..) |row, i| selection_rows_width[i] += textLineSize(buffer, row, 1, Buffer.RowCol.last_col)[0];
                    selection_rows_width[selected_rows - 1] = textLineSize(buffer, end.row, 1, end.col)[0];
                }
            },
        }

        switch (buffer.selection.kind) { // get selection_rows_offset
            .line => {}, // selection_rows_offset should be zero and is zero by default
            .regular => {
                if (start.col > 1) {
                    selection_rows_offset[0] = textLineSize(buffer, start.row, 1, start.col)[0];
                    // The rest should be zero and are zero by default
                }
            },
            .block => {
                if (start.col > 1) {
                    for (start.row..end.row + 1, 0..) |row, i| {
                        selection_rows_offset[i] = textLineSize(buffer, row, 1, start.col)[0];
                    }
                }
            },
        }

        // now render the selection
        var relative_row = buffer_window.relativeBufferRowFromAbsolute(start.row);
        if (!new_line) relative_row -= 1;
        for (selection_rows_width[0..selected_rows], 0..selected_rows) |w, j| {
            if (buffer.selection.kind == .block and w == 0) {
                continue;
            }

            const pos = imgui.getWindowPos();
            const padding = imgui.getStyle().window_padding;
            const y = @intToFloat(f32, j + relative_row) * line_h + padding[1] + pos[1];
            const x = padding[0] + selection_rows_offset[j] + pos[0];

            dl.addRectFilled(.{
                .pmin = .{ x, y },
                .pmax = .{ x + w, y + line_h },
                .col = getCursorRect(.{ 0, 0 }, .{ 0, 0 }).col,
            });
        }
    }

    { // render text
        const start = buffer_window.first_visiable_row;
        const end = buffer_window.lastVisibleRow() + 1;
        for (start..end) |row| {
            const line = getVisibleLine(buffer, &static.buf, row);
            imgui.textUnformatted(line);
        }
    }

    if (buffer_window == &core.focusedBW().?.data) { // render cursor
        const cursor_row = buffer_window.cursor.row;

        var padding = imgui.getStyle().window_padding;
        var win_pos = imgui.getWindowPos();

        var min: [2]f32 = .{ 0, 0 };
        min[0] = win_pos[0] + padding[0];

        var relative_row = @intToFloat(f32, buffer_window.relativeBufferRowFromAbsolute(cursor_row));
        if (!new_line) relative_row -= 1;

        min[1] = (line_h * relative_row) + win_pos[1] + padding[1];

        { // get the x position of the cursor
            const s = textLineSize(buffer, cursor_row, 1, buffer_window.cursor.col);
            min[0] += s[0];
        }

        var max = min;

        { // get width and height
            var slice = buffer.codePointSliceAt(cursor_index) catch unreachable;
            if (slice[0] == '\n') slice = "m"; // newline char doesn't have a size so give it one
            var s = imgui.calcTextSize(slice, .{});
            max[0] += s[0];
            max[1] += line_h;
        }

        var rect = getCursorRect(min, max);

        dl.addRectFilled(.{
            .pmin = rect.leftTop(),
            .pmax = rect.rightBottom(),
            .col = rect.col,
            .rounding = rect.rounding,
            .flags = .{
                .closed = rect.flags.closed,
                .round_corners_top_left = rect.flags.round_corners_top_left,
                .round_corners_top_right = rect.flags.round_corners_top_right,
                .round_corners_bottom_left = rect.flags.round_corners_bottom_left,
                .round_corners_bottom_right = rect.flags.round_corners_bottom_right,
                .round_corners_none = rect.flags.round_corners_none,
            },
        });
    }

    { // invisible button for interactions

        var pos = begin_cursor_pos;
        pos[0] -= imgui.getStyle().window_padding[0];
        imgui.setCursorPos(pos);

        const clicked = imgui.invisibleButton(tmpString("##buffer_window_button ({x})", .{@ptrToInt(buffer_window)}), .{
            .w = width,
            .h = height,
        });
        const focused = imgui.isItemFocused();

        if (clicked or focused) {
            if (buffer_window_node != core.focusedBW().?) core.setFocusedWindow(buffer_window_node);
        }

        return focused or clicked;
    }
}

pub fn getVisibleLine(buffer: *Buffer, array_buf: []u8, row: u64) []u8 {
    const start = buffer.getIndex(.{ .row = row, .col = 1 });
    const end = buffer.getIndex(.{ .row = row, .col = max_visible_cols });
    var iter = Buffer.BufferIterator.init(buffer, start, end);
    var i: u64 = 0;
    while (iter.next()) |string| {
        for (string) |b| {
            array_buf[i] = b;
            i += 1;
        }
    }

    return array_buf[0..i];
}

pub fn textLineSize(buffer: *Buffer, row: u64, col_start: u64, col_end: u64) [2]f32 {
    const start = buffer.getIndex(.{ .row = row, .col = col_start });
    const end = buffer.getIndex(.{ .row = row, .col = col_end });

    var iter = BufferIterator.init(buffer, start, end);
    var size: [2]f32 = .{ 0, 0 };
    while (iter.next()) |string| {
        const s = imgui.calcTextSize(string, .{});
        size[0] += s[0];
        size[1] += s[1];

        if (string[string.len - 1] == '\n') {
            const nls = imgui.calcTextSize("m", .{});
            size[0] += nls[0];
            size[1] += nls[1];
        }
    }

    return size;
}

pub fn getCursorRect(min: [2]f32, max: [2]f32) core.BufferWindow.CursorRect {
    var rect = if (@hasDecl(input_layer, "cursorRect"))
        input_layer.cursorRect(min[0], min[1], max[0], max[1])
    else
        core.BufferWindow.CursorRect{
            .left = min[0],
            .top = min[1],
            .right = max[0],
            .bottom = max[1],
        };

    if (rect.right - rect.left == 0) rect.right += 1;
    if (rect.bottom - rect.top == 0) rect.bottom += 1;

    return rect;
}

pub fn imguiKeyToEditor(key: imgui.Key) core.input.KeyUnion {
    return switch (key) {
        .a => .{ .code_point = 'a' },
        .b => .{ .code_point = 'b' },
        .c => .{ .code_point = 'c' },
        .d => .{ .code_point = 'd' },
        .e => .{ .code_point = 'e' },
        .f => .{ .code_point = 'f' },
        .g => .{ .code_point = 'g' },
        .h => .{ .code_point = 'h' },
        .i => .{ .code_point = 'i' },
        .j => .{ .code_point = 'j' },
        .k => .{ .code_point = 'k' },
        .l => .{ .code_point = 'l' },
        .m => .{ .code_point = 'm' },
        .n => .{ .code_point = 'n' },
        .o => .{ .code_point = 'o' },
        .p => .{ .code_point = 'p' },
        .q => .{ .code_point = 'q' },
        .r => .{ .code_point = 'r' },
        .s => .{ .code_point = 's' },
        .t => .{ .code_point = 't' },
        .u => .{ .code_point = 'u' },
        .v => .{ .code_point = 'v' },
        .w => .{ .code_point = 'w' },
        .x => .{ .code_point = 'x' },
        .y => .{ .code_point = 'y' },
        .z => .{ .code_point = 'z' },

        .zero => .{ .code_point = '0' },
        .one => .{ .code_point = '1' },
        .two => .{ .code_point = '2' },
        .three => .{ .code_point = '3' },
        .four => .{ .code_point = '4' },
        .five => .{ .code_point = '5' },
        .six => .{ .code_point = '6' },
        .seven => .{ .code_point = '7' },
        .eight => .{ .code_point = '8' },
        .nine => .{ .code_point = '9' },

        .keypad_divide => .{ .code_point = '/' },
        .keypad_multiply => .{ .code_point = '*' },
        .keypad_subtract, .minus => .{ .code_point = '-' },
        .keypad_add => .{ .code_point = '+' },
        .keypad_0 => .{ .code_point = '0' },
        .keypad_1 => .{ .code_point = '1' },
        .keypad_2 => .{ .code_point = '2' },
        .keypad_3 => .{ .code_point = '3' },
        .keypad_4 => .{ .code_point = '4' },
        .keypad_5 => .{ .code_point = '5' },
        .keypad_6 => .{ .code_point = '6' },
        .keypad_7 => .{ .code_point = '7' },
        .keypad_8 => .{ .code_point = '8' },
        .keypad_9 => .{ .code_point = '9' },
        .equal, .keypad_equal => .{ .code_point = '=' },
        .left_bracket => .{ .code_point = '[' },
        .right_bracket => .{ .code_point = ']' },
        .back_slash => .{ .code_point = '\\' },
        .semicolon => .{ .code_point = ';' },
        .comma => .{ .code_point = ',' },
        .period => .{ .code_point = '.' },
        .slash => .{ .code_point = '/' },
        .grave_accent => .{ .code_point = '`' },

        .f1 => .{ .function_key = .f1 },
        .f2 => .{ .function_key = .f2 },
        .f3 => .{ .function_key = .f3 },
        .f4 => .{ .function_key = .f4 },
        .f5 => .{ .function_key = .f5 },
        .f6 => .{ .function_key = .f6 },
        .f7 => .{ .function_key = .f7 },
        .f8 => .{ .function_key = .f8 },
        .f9 => .{ .function_key = .f9 },
        .f10 => .{ .function_key = .f10 },
        .f11 => .{ .function_key = .f11 },
        .f12 => .{ .function_key = .f12 },

        .enter, .keypad_enter => .{ .function_key = .enter },

        .escape => .{ .function_key = .escape },
        .tab => .{ .function_key = .tab },
        .num_lock => .{ .function_key = .num_lock },
        .caps_lock => .{ .function_key = .caps_lock },
        .print_screen => .{ .function_key = .print_screen },
        .scroll_lock => .{ .function_key = .scroll_lock },
        .pause => .{ .function_key = .pause },
        .delete => .{ .function_key = .delete },
        .home => .{ .function_key = .home },
        .end => .{ .function_key = .end },
        .page_up => .{ .function_key = .page_up },
        .page_down => .{ .function_key = .page_down },
        .insert => .{ .function_key = .insert },
        .left_arrow => .{ .function_key = .left },
        .right_arrow => .{ .function_key = .right },
        .up_arrow => .{ .function_key = .up },
        .down_arrow => .{ .function_key = .down },
        .back_space => .{ .function_key = .backspace },
        .space => .{ .function_key = .space },

        // .keypad_decimal=>, // ?? idk what this is
        // .apostrophe=>.{.code_point = '-'}, ?? idk what this is

        // .left_shift=>.{.function_key = .enter},
        // .right_shift=>.{.function_key = .enter},
        // .left_control=>.{.function_key = .enter},
        // .right_control=>.{.function_key = .enter},
        // .left_alt=>.{.function_key = .enter},
        // .right_alt=>.{.function_key = .enter},
        // .left_super=>.{.function_key = .enter},
        // .right_super=>.{.function_key = .enter},
        // .menu=>.{.function_key = .enter},
        // .f25 => .{ .function_key = .f25 },
        else => .{ .function_key = .unknown },
    };
}

pub fn modToEditorMod(shift: bool, control: bool, alt: bool) core.input.Modifiers {
    var mod_int: u3 = 0;
    if (shift) mod_int |= @enumToInt(core.input.Modifiers.shift);
    if (control) mod_int |= @enumToInt(core.input.Modifiers.control);
    if (alt) mod_int |= @enumToInt(core.input.Modifiers.alt);

    return @intToEnum(core.input.Modifiers, mod_int);
}
