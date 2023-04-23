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
const BufferWindowNode = core.BufferWindowNode;
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
    if (buffers_focused and core.focusedBW() == null)
        globals.ui.focused_buffer_window = globals.ui.visiable_buffers_tree.root;
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
    buffer_window.visible_lines = @floatToInt(u32, std.math.floor(height / line_h)) -| 2;
    buffer_window.windowFollowCursor();

    var buffer = buffer_window.buffer;

    const cursor_index = buffer.getIndex(buffer_window.cursor);

    const start_row = buffer_window.first_visiable_row;
    const end_row = buffer_window.lastVisibleRow();
    for (start_row..end_row + 1, 1..) |row, on_screen_row| {
        // render text
        const line = getVisibleLine(buffer, &static.buf, row);
        imgui.textUnformatted(line);

        const pos = imgui.getWindowPos();
        const padding = imgui.getStyle().window_padding;
        const abs_x = padding[0] + pos[0];
        var abs_y = @intToFloat(f32, on_screen_row) * line_h + padding[1] + pos[1];
        if (!new_line) abs_y -= line_h;

        // render selection
        const selection = buffer.selection.get(buffer_window.cursor);
        if (buffer.selection.selected() and buffer_window_node == core.focusedBW() and
            row >= selection.start.row and row <= selection.end.row)
        {
            const start_col = switch (buffer.selection.kind) {
                .line => 1,
                .block => selection.start.col,
                .regular => if (row > selection.start.row) 1 else selection.start.col,
            };
            const end_col = switch (buffer.selection.kind) {
                .line => Buffer.RowCol.last_col,
                .block => selection.end.col,
                .regular => if (row < selection.end.row) Buffer.RowCol.last_col else selection.end.col,
            };

            const size = textLineSize(buffer, line, row, start_col, end_col);
            const x_offset = if (start_col == 1) 0 else textLineSize(buffer, line, row, 1, start_col)[0];

            const x = abs_x + x_offset;
            dl.addRectFilled(.{
                .pmin = .{ x, abs_y },
                .pmax = .{ x + size[0], abs_y + line_h },
                .col = getCursorRect(.{ 0, 0 }, .{ 0, 0 }).col,
            });
        }

        // render cursor
        if (row == buffer_window.cursor.row and buffer_window_node == core.focusedBW()) {
            const offset = textLineSize(buffer, line, row, 1, buffer_window.cursor.col);
            const size = blk: {
                var slice = buffer.codePointSliceAt(cursor_index) catch unreachable;
                if (slice[0] == '\n') slice = "m"; // newline char doesn't have a size so give it one
                break :blk imgui.calcTextSize(slice, .{});
            };

            const x = abs_x + offset[0];
            const min = [2]f32{ x, abs_y };
            const max = [2]f32{ x + size[0], abs_y + line_h };

            const crect = getCursorRect(min, max);
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
    }

    { // invisible button for interactions

        var pos = begin_cursor_pos;
        pos[0] -= imgui.getStyle().window_padding[0];
        imgui.setCursorPos(pos);

        var clicked = imgui.invisibleButton(tmpString("##buffer_window_button ({x})", .{@ptrToInt(buffer_window)}), .{
            .w = width,
            .h = height,
        });

        var focused = imgui.isItemFocused();
        if (clicked or focused) {
            if (buffer_window_node != core.focusedBW()) core.setFocusedWindow(buffer_window_node);
        }

        return focused;
    }
}

pub fn getVisibleLine(buffer: *Buffer, array_buf: []u8, row: u64) []u8 {
    const start = buffer.indexOfFirstByteAtRow(row);
    const end = start + std.math.min(max_visible_bytes, buffer.lineSize(row));
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

pub fn textLineSize(buffer: *Buffer, line: []const u8, row: u64, col_start: u64, col_end: u64) [2]f32 {
    const line_start = buffer.indexOfFirstByteAtRow(row);
    const start = buffer.getIndex(.{ .row = row, .col = col_start }) - line_start;
    const end = buffer.getIndex(.{ .row = row, .col = col_end }) - line_start;

    const s = imgui.calcTextSize(line[start..end], .{});
    var size: [2]f32 = .{ 0, 0 };
    size[0] += s[0];
    size[1] += s[1];

    if (line[0] == '\n') {
        const nls = imgui.calcTextSize("m", .{});
        size[0] += nls[0];
        size[1] += nls[1];
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
