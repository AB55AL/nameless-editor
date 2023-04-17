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

const KeyAndDuration = struct {
    key: core.input.Key,
    duration: f32,
};

fn greaterThan(context: void, a: KeyAndDuration, b: KeyAndDuration) std.math.Order {
    _ = context;
    return std.math.order(a.duration, b.duration).invert();
}

pub fn buffers(allocator: std.mem.Allocator) !void {
    _ = imgui.begin("buffers", .{ .flags = .{
        .no_nav_focus = true,
        .no_resize = true,
        .no_scroll_with_mouse = true,
        .no_scrollbar = true,
    } });
    defer imgui.end();

    var bw_tree = core.globals.ui.visiable_buffers_tree.root orelse {
        core.command_line.open();
        return;
    };

    var size = imgui.getWindowSize();
    var rect = core.BufferWindow.Rect{ .w = size[0], .h = size[1] };
    var windows = try core.BufferWindow.getAndSetWindows(bw_tree, allocator, rect);
    defer allocator.free(windows);
    for (windows) |bw| {
        imgui.setCursorPos(.{ bw.data.rect.x, bw.data.rect.y });
        bufferWidget(&bw.data, bw.data.rect.w, bw.data.rect.h);
    }
}

pub fn bufferWidget(buffer_window: *core.BufferWindow, width: f32, height: f32) void {
    var id_buf: [100:0]u8 = undefined;
    var id = std.fmt.bufPrint(&id_buf, "buffer_window ({x})", .{@ptrToInt(buffer_window)}) catch unreachable;
    id_buf[id.len] = 0;

    _ = imgui.beginChild(&id_buf, .{
        .w = width,
        .h = height,
        .border = true,
        .flags = .{ .no_scroll_with_mouse = true, .no_scrollbar = true },
    });
    defer imgui.endChild();

    imgui.newLine();

    var line_h = imgui.getTextLineHeightWithSpacing();
    buffer_window.visible_lines = @floatToInt(u32, std.math.floor(height / line_h));
    buffer_window.resetBufferWindowRowsToBufferCursor();

    var buffer = buffer_window.buffer;

    {
        var from = buffer_window.first_visiable_row;
        var to = buffer_window.lastVisibleRow();
        var iter = LineIterator.init(buffer, from, to);
        while (iter.next()) |string| {
            imgui.textUnformatted(string);
            if (string[string.len - 1] != '\n') imgui.sameLine(.{ .spacing = 0 });
        }
    }

    //
    // render cursor
    //
    const cursor_row = buffer.getRowAndCol(buffer.cursor_index).row;
    var dl = imgui.getWindowDrawList();

    var padding = imgui.getStyle().window_padding;
    var win_pos = imgui.getWindowPos();
    var min: [2]f32 = .{ 0, 0 };
    min[0] = win_pos[0] + padding[0];
    min[1] = (line_h * @intToFloat(f32, buffer_window.relativeBufferRowFromAbsolute(cursor_row))) + win_pos[1] + padding[1];

    { // get the x position of the cursor
        var from = buffer.indexOfFirstByteAtRow(cursor_row);
        var to = buffer.cursor_index;
        var iter = BufferIterator.init(buffer, from, to);
        while (iter.next()) |string| {
            var s = imgui.calcTextSize(string, .{});
            min[0] += s[0];
        }
    }

    var max = min;

    { // get width and height
        var slice = buffer.codePointSliceAt(buffer.cursor_index) catch unreachable;
        var s = imgui.calcTextSize(slice, .{});
        max[0] += s[0];
        max[1] += s[1];
    }

    dl.addRect(.{
        .pmin = min,
        .pmax = max,
        .col = 0xFF0000_FF,
    });
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
