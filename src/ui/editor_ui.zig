const std = @import("std");
const print = std.debug.print;
const math = std.math;
const unicode = std.unicode;

const input_layer = @import("input_layer");
const imgui = @import("imgui");
const glfw = @import("glfw");

const core = @import("core");
const utils = core.utils;

const getBuffer = core.getBuffer;

const Buffer = core.Buffer;
const BufferWindow = core.BufferWindow;
const BufferWindowNode = core.BufferWindowNode;
const BufferIterator = core.Buffer.BufferIterator;
const LineIterator = core.Buffer.LineIterator;
const BufferDisplayer = core.BufferDisplayer;
const ColorRange = core.BufferDisplayer.ColorRange;
const RowInfo = core.BufferDisplayer.RowInfo;

const max_visible_rows: u64 = 4000;
const max_visible_cols: u64 = 4000;
const max_visible_bytes = max_visible_cols * 4; // multiply by 4 because a UTF-8 sequence can be 4 bytes long

pub fn tmpStringZ(comptime fmt: []const u8, args: anytype) [:0]u8 {
    const static = struct {
        var buf: [max_visible_bytes + 1:0]u8 = undefined;
    };
    var slice = std.fmt.bufPrintZ(&static.buf, fmt, args) catch {
        static.buf[static.buf.len - 1] = 0;
        return static.buf[0 .. static.buf.len - 1 :0];
    };

    return slice;
}

pub fn tmpString(comptime fmt: []const u8, args: anytype) []u8 {
    const static = struct {
        var buf: [max_visible_bytes]u8 = undefined;
    };
    var slice = std.fmt.bufPrint(&static.buf, fmt, args) catch
        static.buf[0..static.buf.len];

    return slice;
}

pub fn buffers(arena: std.mem.Allocator, os_window_width: f32, os_window_height: f32) !void {
    var gs = core.globals.globals.?;

    const buffer_win_flags = imgui.WindowFlags{ .no_nav_focus = true, .no_resize = true, .no_scroll_with_mouse = true, .no_scrollbar = true, .no_title_bar = false, .no_collapse = true };
    const cli_win_flags = imgui.WindowFlags{ .no_nav_focus = true, .no_scroll_with_mouse = true, .no_scrollbar = true, .no_title_bar = true, .no_resize = true };
    var buffers_focused = false;
    if (!core.cliIsOpen()) gs.focused_cursor_rect = null;

    { // Remove all buffer windows that have invalid buffers

        var wins = try gs.visiable_buffers_tree.treeToArray(arena);
        var wins_to_close = std.ArrayList(*BufferWindowNode).init(arena);
        for (wins) |win|
            if (getBuffer(win.data.bhandle) == null) try wins_to_close.append(win);

        for (wins_to_close.items) |win| core.closeBW(win);
    }

    cli: {
        if (core.cliIsOpen()) {
            // get cli window pos and size
            const center = imgui.getMainViewport().getCenter();

            const m_size = imgui.calcTextSize("m", .{})[0];
            var size = [2]f32{ 0, 0 };
            size[0] = std.math.max(m_size * 20, m_size * @intToFloat(f32, core.cliBuffer().size() + 2));
            size[1] = imgui.getTextLineHeightWithSpacing() * 2;

            const x = if (core.focusedCursorRect()) |rect| rect.right() else center[0] - (size[0] / 2);
            const y = if (core.focusedCursorRect()) |rect| rect.top() else center[1] - (size[1] / 2);

            imgui.setNextWindowPos(.{ .x = x, .y = y, .cond = .appearing, .pivot_x = 0, .pivot_y = 0 });
            imgui.setNextWindowSize(.{ .w = size[0], .h = size[1], .cond = .always });
            imgui.setNextWindowFocus();

            const padding = imgui.getStyle().window_padding;
            core.cliBW().data.rect.x = x - padding[0];
            core.cliBW().data.rect.y = y - padding[1];
            const res = bufferWidget("command line", arena, core.cliBW(), size[0], size[1], cli_win_flags) catch break :cli;
            buffers_focused = buffers_focused or res;
        }
    }

    buffers: {
        if (!gs.show_buffers) break :buffers;

        if (gs.visiable_buffers_tree.root == null)
            break :buffers;

        var rect = core.Rect{ .w = os_window_width, .h = os_window_height };
        var windows = try core.BufferWindow.getAndSetWindows(&gs.visiable_buffers_tree, arena, rect);
        for (windows) |bw| {
            if (bw == core.focusedBW() and gs.focus_buffers) {
                imgui.setNextWindowFocus();
                gs.focus_buffers = false;
                core.closeCLI(false, false);
            }
            imgui.setNextWindowPos(.{ .x = bw.data.rect.x, .y = bw.data.rect.y });
            imgui.setNextWindowSize(.{ .w = bw.data.rect.w, .h = bw.data.rect.h, .cond = .always });

            const file_path = getBuffer(bw.data.bhandle).?.metadata.file_path;
            var win_name = tmpStringZ("{s}##({x})", .{ file_path, @ptrToInt(bw) });
            const res = bufferWidget(win_name, arena, bw, bw.data.rect.w, bw.data.rect.h, buffer_win_flags) catch continue;
            buffers_focused = buffers_focused or res;
        }
    }

    if (!buffers_focused) gs.focused_buffer_window = null;
    if (buffers_focused and core.focusedBW() == null)
        gs.focused_buffer_window = gs.visiable_buffers_tree.root;
}

pub fn bufferWidget(window_name: [:0]const u8, arena: std.mem.Allocator, buffer_window_node: *core.BufferWindowNode, width: f32, height: f32, win_flags: imgui.WindowFlags) !bool {
    const child_flags = imgui.WindowFlags{ .no_scroll_with_mouse = true, .no_scrollbar = true, .always_auto_resize = true };
    _ = width;

    imgui.pushStyleColor1u(.{ .idx = .window_bg, .c = buffer_window_node.data.options.color.bg });
    imgui.pushStyleColor1u(.{ .idx = .text, .c = buffer_window_node.data.options.color.text });
    defer imgui.popStyleColor(.{ .count = 2 });

    _ = imgui.begin(window_name, .{ .flags = win_flags });
    defer imgui.end();

    var buffer_window = &buffer_window_node.data;

    var line_h = imgui.getTextLineHeightWithSpacing();
    buffer_window.visible_lines = @floatToInt(u32, std.math.floor(height / line_h)) -| 2;
    buffer_window.windowFollowCursor();

    var focused = imgui.isWindowFocused(.{});

    var dres = displayLineNumber(buffer_window_node, child_flags);
    focused = focused or dres;

    imgui.sameLine(.{});

    var bufres = try bufferText(buffer_window_node, arena, child_flags);
    focused = focused or bufres;

    // keep the buffer focused
    if (focused) {
        if (buffer_window_node != core.focusedBW()) core.setFocusedBW(buffer_window_node);
    }

    return focused;
}

fn displayLineNumber(buffer_window_node: *BufferWindowNode, child_flags: imgui.WindowFlags) bool {
    var buffer_window = &buffer_window_node.data;
    const start_row = buffer_window.first_visiable_row;
    const end_row = buffer_window.lastVisibleRow();

    if (buffer_window.options.line_number == .none) return false;

    const w = imgui.calcTextSize(tmpStringZ("{}", .{end_row}), .{})[0];
    _ = imgui.beginChild("displayLineNumber", .{ .w = w, .flags = child_flags });
    defer imgui.endChild();

    blk: {
        const buffer = getBuffer(buffer_window.bhandle) orelse break :blk;
        const cursor = buffer_window.cursor() orelse break :blk;
        const cursor_row = buffer.rowOfIndex(cursor).row;
        const on_screen_cursor_row = buffer_window.relativeBufferRowFromAbsolute(cursor_row);

        switch (buffer_window.options.line_number) {
            .none => {},
            .relative => {
                var r = on_screen_cursor_row - 1;
                while (r > 0) : (r -= 1) imgui.text("{}", .{r});
                imgui.text("{}", .{cursor_row});
                for (1..buffer_window.lastVisibleRow()) |row| imgui.text("{}", .{row});
            },
            .absolute => {
                for (start_row..end_row + 1) |row|
                    imgui.text("{}", .{row});
            },
        }
    }

    return imgui.isWindowFocused(.{});
}

fn bufferText(buffer_window_node: *BufferWindowNode, arena: std.mem.Allocator, child_flags: imgui.WindowFlags) !bool {
    var gs = core.globals.globals.?;

    const static = struct {
        pub var buf: [max_visible_bytes]u8 = undefined;
    };

    var dl = imgui.getWindowDrawList();

    var buffer_window = &buffer_window_node.data;
    var buffer = getBuffer(buffer_window.bhandle) orelse return false;
    const start_row = buffer_window.first_visiable_row;
    const end_row = buffer_window.lastVisibleRow();

    var line_h = imgui.getTextLineHeightWithSpacing();

    const buffer_cursor = buffer_window.cursor();

    _ = imgui.beginChild("bufferText", .{ .border = false, .flags = child_flags });
    defer imgui.endChild();

    var displayer = gs.buffer_displayers.get(buffer.metadata.buffer_type);
    var display_info: []RowInfo = if (displayer) |dis|
        try dis.get(arena, buffer_window, buffer, 0)
    else
        &.{};

    const abs_pos = imgui.getCursorScreenPos();
    for (start_row..end_row + 1, 0..) |row, on_screen_row| {
        // render text
        const line = getVisibleLine(buffer, &static.buf, row);

        var row_info = getInfoOfRow(display_info, row);
        if (row_info != null and row_info.?.color_ranges.len > 0) {
            var info = row_info.?;

            if (!std.sort.isSorted(ColorRange, info.color_ranges, void, ColorRange.lessThan)) {
                std.sort.sort(ColorRange, info.color_ranges, void, ColorRange.lessThan);
            }

            var iter = ColorRange.ColorRangeIterator.init(0xFFFFFFFF, line.len, info.color_ranges);
            while (iter.next()) |cr| {
                var slice = line[cr.start..cr.end];
                imgui.textUnformattedColored(hexToFloatColor(cr.color), slice);
                imgui.sameLine(.{ .spacing = 0 });
            }

            imgui.newLine();
        } else {
            imgui.textUnformatted(line);
        }

        const abs_x = abs_pos[0];
        const abs_y = (@intToFloat(f32, on_screen_row) * line_h) + abs_pos[1];

        // render selection
        render_selection: {
            const cursor = buffer_cursor orelse break :render_selection;
            const selection = buffer.selection.get(buffer.getPoint(cursor));
            if (buffer.selection.selected() and buffer_window_node == core.focusedBW() and
                row >= selection.start.row and row <= selection.end.row)
            {
                const relative_line_end = buffer.indexOfLastByteAtRow(row) - buffer.indexOfFirstByteAtRow(row) + 1;
                // indices are relative to the begging of the line
                const start_index = switch (buffer.selection.kind) {
                    .line => 0,
                    .block => buffer.getColIndex(selection.start),
                    .regular => if (row > selection.start.row) 0 else buffer.getColIndex(selection.start),
                };
                const end_index = switch (buffer.selection.kind) {
                    .line => relative_line_end,
                    .block => buffer.getColIndex(selection.end),
                    .regular => if (row < selection.end.row) relative_line_end else buffer.getColIndex(selection.end),
                };

                const size = textLineSize(line, start_index, end_index);
                const x_offset = if (start_index == 0) 0 else textLineSize(line, 0, start_index)[0];

                const x = abs_x + x_offset;
                dl.addRectFilled(.{
                    .pmin = .{ x, abs_y },
                    .pmax = .{ x + size[0], abs_y + line_h },
                    .col = getCursorRect(.{ 0, 0 }, .{ 0, 0 }).col,
                });
            }
        }

        // render cursor
        render_cursor: {
            const cursor = buffer_cursor orelse break :render_cursor;

            if (row == buffer.rowOfIndex(cursor).row and buffer_window_node == core.focusedBW()) {
                const offset = if (cursor == buffer.indexOfFirstByteAtRow(row))
                    [2]f32{ 0, 0 }
                else
                    textLineSize(line, 0, cursor - buffer.indexOfFirstByteAtRow(row));

                const size = blk: {
                    var slice = buffer.codePointSliceAt(cursor);
                    if (slice[0] == '\n') slice = "m"; // newline char doesn't have a size so give it one
                    break :blk imgui.calcTextSize(slice, .{});
                };

                const x = abs_x + offset[0];
                const min = [2]f32{ x, abs_y };
                const max = [2]f32{ x + size[0], abs_y + line_h };

                const crect = getCursorRect(min, max);
                gs.focused_cursor_rect = crect.rect;

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
    } // for loop

    return imgui.isWindowFocused(.{});
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

pub fn textLineSize(line: []const u8, index_start: u64, index_end: u64) [2]f32 {
    const start = index_start;
    const end = index_end;

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
    var gs = core.globals.globals.?;

    if (gs.notifications.count() == 0)
        return;

    var width: f32 = 0;

    {
        var iter = gs.notifications.data.iterator();
        while (iter.next()) |kv| {
            var n = kv.key_ptr.*;
            const title_size = imgui.calcTextSize(n.title, .{});
            const message_size = imgui.calcTextSize(n.message, .{});
            width = std.math.max3(width, title_size[0], message_size[0]);
        }
    }

    const s = imgui.getStyle();
    const padding = s.window_padding[0] + s.frame_padding[0] + s.cell_padding[0];
    const window_size = imgui.getMainViewport().getSize();
    const x = window_size[0] - width - padding;

    imgui.setNextWindowPos(.{ .x = x, .y = 0 });

    _ = imgui.begin("Notifications", .{
        .flags = .{
            .no_title_bar = true,
            .no_resize = true,
            .no_move = true,
            .no_scrollbar = true,
            .no_scroll_with_mouse = true,
            .no_collapse = true,
            .always_auto_resize = true,
            .no_background = true,
            .no_saved_settings = true,
            .menu_bar = false,
            .no_focus_on_appearing = true,
        },
    });
    defer imgui.end();

    var iter = gs.notifications.data.iterator();
    while (iter.next()) |kv| {
        var n = kv.key_ptr;
        if (n.remaining_time <= 0) continue;

        var text = tmpStringZ("{d:<.0} x{:>}", .{ n.remaining_time, n.duplicates });
        imgui.textUnformatted(text);

        text = tmpStringZ("{s}\n{s}", .{ n.title, n.message });
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

pub fn hexToFloatColor(color: u32) [4]f32 {
    var r = @intToFloat(f32, (color & 0xFF_000000) >> 24) / 255;
    var g = @intToFloat(f32, (color & 0x00_FF_0000) >> 16) / 255;
    var b = @intToFloat(f32, (color & 0x0000_FF_00) >> 8) / 255;
    var a = @intToFloat(f32, (color & 0x000000_FF)) / 255;

    return .{ r, g, b, a };
}

fn getInfoOfRow(row_info: []RowInfo, row: u64) ?RowInfo {
    for (row_info) |ri| if (ri.row == row) return ri;
    return null;
}
