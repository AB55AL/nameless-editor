const std = @import("std");

const glfw = @import("glfw");
const core = @import("core");

const globals = core.globals;

const modToEditorMod = @import("ui.zig").modToEditorMod;

pub fn keyCallback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    if (action == .release) return;
    _ = scancode;
    _ = window;

    const k = glfwKeyToEditorKey(key, mods);
    globals.input.key_queue.insert(0, k) catch return;
}

pub fn charCallback(window: glfw.Window, codepoint: u21) void {
    _ = window;
    globals.input.char_queue.insert(0, codepoint) catch return;
}

pub fn glfwKeyToEditorKey(glfw_key: glfw.Key, mods: glfw.Mods) core.input.Key {
    const mod = modToEditorMod(mods.shift, mods.control, mods.alt);

    const key: core.input.KeyUnion = switch (glfw_key) {
        // zig fmt: off
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

        .zero, .kp_0  => .{ .code_point = '0' },
        .one, .kp_1   => .{ .code_point = '1' },
        .two, .kp_2   => .{ .code_point = '2' },
        .three, .kp_3 => .{ .code_point = '3' },
        .four, .kp_4  => .{ .code_point = '4' },
        .five, .kp_5  => .{ .code_point = '5' },
        .six, .kp_6   => .{ .code_point = '6' },
        .seven, .kp_7 => .{ .code_point = '7' },
        .eight, .kp_8 => .{ .code_point = '8' },
        .nine, .kp_9  => .{ .code_point = '9' },

        .kp_divide           => .{ .code_point = '/' },
        .kp_multiply         => .{ .code_point = '*' },
        .kp_subtract, .minus => .{ .code_point = '-' },
        .kp_add              => .{ .code_point = '+' },
        .equal, .kp_equal    => .{ .code_point = '=' },
        .left_bracket        => .{ .code_point = '[' },
        .right_bracket       => .{ .code_point = ']' },
        .backslash           => .{ .code_point = '\\' },
        .semicolon           => .{ .code_point = ';' },
        .comma               => .{ .code_point = ',' },
        .period, .kp_decimal => .{ .code_point = '.' },
        .slash               => .{ .code_point = '/' },
        .grave_accent        => .{ .code_point = '`' },
        .apostrophe          => .{ .code_point = '\'' },

        .F1  => .{ .function_key = .f1 },
        .F2  => .{ .function_key = .f2 },
        .F3  => .{ .function_key = .f3 },
        .F4  => .{ .function_key = .f4 },
        .F5  => .{ .function_key = .f5 },
        .F6  => .{ .function_key = .f6 },
        .F7  => .{ .function_key = .f7 },
        .F8  => .{ .function_key = .f8 },
        .F9  => .{ .function_key = .f9 },
        .F10 => .{ .function_key = .f10 },
        .F11 => .{ .function_key = .f11 },
        .F12 => .{ .function_key = .f12 },
        .F13 => .{ .function_key = .f13 },
        .F14 => .{ .function_key = .f14 },
        .F15 => .{ .function_key = .f15 },
        .F16 => .{ .function_key = .f16 },
        .F17 => .{ .function_key = .f17 },
        .F18 => .{ .function_key = .f18 },
        .F19 => .{ .function_key = .f19 },
        .F20 => .{ .function_key = .f20 },
        .F21 => .{ .function_key = .f21 },
        .F22 => .{ .function_key = .f22 },
        .F23 => .{ .function_key = .f23 },
        .F24 => .{ .function_key = .f24 },

        .enter, .kp_enter => .{ .function_key = .enter },

        .escape        => .{ .function_key = .escape },
        .tab           => .{ .function_key = .tab },
        .num_lock      => .{ .function_key = .num_lock },
        .caps_lock     => .{ .function_key = .caps_lock },
        .print_screen  => .{ .function_key = .print_screen },
        .scroll_lock   => .{ .function_key = .scroll_lock },
        .pause         => .{ .function_key = .pause },
        .delete        => .{ .function_key = .delete },
        .home          => .{ .function_key = .home },
        .end           => .{ .function_key = .end },
        .page_up       => .{ .function_key = .page_up },
        .page_down     => .{ .function_key = .page_down },
        .insert        => .{ .function_key = .insert },
        .left          => .{ .function_key = .left },
        .right         => .{ .function_key = .right },
        .up            => .{ .function_key = .up },
        .down          => .{ .function_key = .down },
        .backspace     => .{ .function_key = .backspace },
        .space         => .{ .function_key = .space },

        .left_shift    => .{ .function_key = .left_shift },
        .right_shift   => .{ .function_key = .right_shift },
        .left_control  => .{ .function_key = .left_control },
        .right_control => .{ .function_key = .right_control },
        .left_alt      => .{ .function_key = .left_alt },
        .right_alt     => .{ .function_key = .right_alt },

        else => .{ .function_key = .unknown },
        // zig fmt: on
    };

    return .{
        .key = key,
        .mod = mod,
    };
}
