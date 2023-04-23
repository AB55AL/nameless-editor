const std = @import("std");
const print = std.debug.print;
const math = std.math;
const unicode = std.unicode;

const input_layer = @import("input_layer");
const imgui = @import("imgui");
const glfw = @import("glfw");

const core = @import("core");
const utils = core.utils;

const globals = core.globals;

const Buffer = core.Buffer;
const BufferWindow = core.BufferWindow;
const BufferIterator = core.Buffer.BufferIterator;
const LineIterator = core.Buffer.LineIterator;

const max_visible_rows: u64 = 4000;
const max_visible_cols: u64 = 4000;
const max_visible_bytes = max_visible_cols * 4; // multiply by 4 because a UTF-8 sequence can be 4 bytes long

pub fn tmpString(comptime fmt: []const u8, args: anytype) [:0]u8 {
    const static = struct {
        var buf: [max_visible_bytes + 1:0]u8 = undefined;
    };
    var slice = std.fmt.bufPrintZ(&static.buf, fmt, args) catch {
        static.buf[static.buf.len - 1] = 0;
        return static.buf[0 .. static.buf.len - 1 :0];
    };

    return slice;
}

pub fn buffers(allocator: std.mem.Allocator) !void {
    var buffers_focused = false;
    if (!globals.editor.command_line_is_open) globals.ui.focused_cursor_rect = null;

    buffers: {
        if (globals.ui.focus_buffers) {
            imgui.setNextWindowFocus();
            globals.ui.focus_buffers = false;

            core.command_line.close(false, false);
        }

        imgui.setNextWindowPos(.{ .x = 0, .y = 0 });
        defer imgui.end();
        if (!imgui.begin("buffers", .{ .flags = .{
            .no_nav_focus = true,
            .no_resize = false,
            .no_scroll_with_mouse = true,
            .no_scrollbar = true,
        } })) break :buffers;

        buffers_focused = imgui.isWindowFocused(.{});

        if (globals.ui.visiable_buffers_tree.root == null) {
            core.command_line.open();
            break :buffers;
        }

        var size = imgui.getWindowSize();
        var rect = core.Rect{ .w = size[0], .h = size[1] };
        var windows = try core.BufferWindow.getAndSetWindows(&globals.ui.visiable_buffers_tree, allocator, rect);
        defer allocator.free(windows);
        for (windows) |bw| {
            imgui.setCursorPos(.{ bw.data.rect.x, bw.data.rect.y });

            const padding = imgui.getStyle().window_padding;
            bw.data.rect.x -= padding[0];
            bw.data.rect.y -= padding[1];

            const res = bufferWidget(bw, true, bw.data.rect.w, bw.data.rect.h);
            buffers_focused = buffers_focused or res;
        }
    }

    if (globals.editor.command_line_is_open) {
        const center = imgui.getMainViewport().getCenter();

        const m_size = imgui.calcTextSize("m", .{})[0];
        var size = [2]f32{ 0, 0 };
        size[0] = std.math.max(m_size * 20, m_size * @intToFloat(f32, globals.editor.command_line_buffer.size() + 2));
        size[1] = imgui.getTextLineHeightWithSpacing() * 2;

        const x = if (core.focusedCursorRect()) |rect| rect.right() else center[0] - (size[0] / 2);
        const y = if (core.focusedCursorRect()) |rect| rect.top() else center[1] - (size[1] / 2);

        imgui.setNextWindowPos(.{ .x = x, .y = y, .cond = .appearing, .pivot_x = 0, .pivot_y = 0 });
        imgui.setNextWindowSize(.{ .w = size[0], .h = size[1], .cond = .always });
        _ = imgui.begin("command line", .{
            .flags = .{
                .no_nav_focus = true,
                .no_scroll_with_mouse = true,
                .no_scrollbar = true,
                .no_title_bar = true,
                .no_resize = true,
            },
        });
        defer imgui.end();

        buffers_focused = buffers_focused or imgui.isWindowFocused(.{});

        const padding = imgui.getStyle().window_padding;
        globals.ui.command_line_buffer_window.data.rect.x = x - padding[0];
        globals.ui.command_line_buffer_window.data.rect.y = y - padding[1];
        const res = bufferWidget(&globals.ui.command_line_buffer_window, false, size[0], size[1]);
        buffers_focused = buffers_focused or res;
    }

    if (!buffers_focused) globals.ui.focused_buffer_window = null;
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
    buffer_window.windowFollowCursor();

    var buffer = buffer_window.buffer;

    const cursor_index = buffer.getIndex(buffer_window.cursor);

    // render selection
    const selection = buffer.selection.get(buffer_window.cursor);
    if (buffer.selection.selected() and !std.meta.eql(buffer.selection.anchor, buffer_window.cursor)) {
        // bound the selection rows between visible rows
        const start = selection.start.max(.{ .row = buffer_window.first_visiable_row, .col = 1 });
        const end = selection.end.min(.{ .row = buffer_window.lastVisibleRow(), .col = selection.end.col });

        const selected_rows = std.math.min(max_visible_rows, (end.row - start.row + 1));
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

    var focused = false;
    { // invisible button for interactions

        var pos = begin_cursor_pos;
        pos[0] -= imgui.getStyle().window_padding[0];
        imgui.setCursorPos(pos);

        var clicked = imgui.invisibleButton(tmpString("##buffer_window_button ({x})", .{@ptrToInt(buffer_window)}), .{
            .w = width,
            .h = height,
        });

        focused = imgui.isItemFocused();
        if (clicked or focused) {
            if (buffer_window_node != core.focusedBW()) core.setFocusedWindow(buffer_window_node);
        }
    }

    if (core.focusedBW() != null and buffer_window == &core.focusedBW().?.data) { // render cursor
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

        var crect = getCursorRect(min, max);
        globals.ui.focused_cursor_rect = crect.rect;

        dl.addRectFilled(.{
            .pmin = crect.rect.leftTop(),
            .pmax = crect.rect.rightBottom(),
            .col = crect.col,
            .rounding = crect.rounding,
            .flags = .{
                .closed = crect.flags.closed,
                .round_corners_top_left = crect.flags.round_corners_top_left,
                .round_corners_top_right = crect.flags.round_corners_top_right,
                .round_corners_bottom_left = crect.flags.round_corners_bottom_left,
                .round_corners_bottom_right = crect.flags.round_corners_bottom_right,
                .round_corners_none = crect.flags.round_corners_none,
            },
        });
    }

    return focused;
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
    var crect = if (@hasDecl(input_layer, "cursorRect"))
        input_layer.cursorRect(core.Rect.fromMinMax(min, max))
    else
        core.BufferWindow.CursorRect{ .rect = core.Rect.fromMinMax(min, max) };

    if (crect.rect.w == 0) crect.rect.w = 1;
    if (crect.rect.h == 0) crect.rect.h = 1;

    return crect;
}

pub fn notifications() void {
    if (core.ui.notifications.slice().len == 0) return;

    var width: f32 = 0;

    var notifys = core.ui.notifications.slice();
    for (notifys) |n| {
        const title_size = imgui.calcTextSize(n.title, .{});
        const message_size = imgui.calcTextSize(n.message, .{});
        width = std.math.max3(width, title_size[0], message_size[0]);
    }

    const s = imgui.getStyle();
    const padding = s.window_padding[0] + s.frame_padding[0] + s.cell_padding[0];
    const window_size = imgui.getMainViewport().getSize();
    const x = window_size[0] - width - padding;

    imgui.setNextWindowPos(.{ .x = x, .y = 0 });

    _ = imgui.begin("Notifications", .{
        .flags = .{ .no_title_bar = true, .no_resize = true, .no_move = true, .no_scrollbar = true, .no_scroll_with_mouse = true, .no_collapse = true, .always_auto_resize = false, .no_background = true, .no_saved_settings = true, .no_mouse_inputs = false, .menu_bar = false, .horizontal_scrollbar = false, .no_focus_on_appearing = true, .no_bring_to_front_on_focus = false, .always_vertical_scrollbar = false, .always_horizontal_scrollbar = false, .always_use_window_padding = false, .no_nav_inputs = false, .no_nav_focus = false, .unsaved_document = false },
    });
    defer imgui.end();

    for (notifys) |*n| {
        if (n.remaining_time <= 0) continue;

        var text = tmpString("{d:<.0} x{:>}", .{ n.remaining_time, n.duplicates });
        imgui.textUnformatted(text);

        text = tmpString("{s}\n{s}", .{ n.title, n.message });
        if (imgui.button(text, .{})) n.remaining_time = 0;
    }
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
