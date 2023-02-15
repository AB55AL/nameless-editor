const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const ArrayList = std.ArrayList;

const freetype = @import("freetype");
const glfw = @import("glfw");
const Mods = glfw.Mods;
const input = @import("input.zig");

const editor = @import("../globals.zig").editor;
const ui = @import("../globals.zig").ui;
const Buffer = @import("buffer.zig");

const input_layer = @import("input_layer");

/// Sends a UTF-8 encoded code point to the input_layer
pub fn characterInputCallback(window: glfw.Window, code_point: u21) void {
    _ = window;
    var utf8_bytes: [4]u8 = undefined;
    var bytes = unicode.utf8Encode(code_point, &utf8_bytes) catch unreachable;
    input_layer.characterInput(utf8_bytes[0..bytes]);
}

pub fn keyInputCallback(window: glfw.Window, glfw_key: glfw.Key, scancode: i32, action: glfw.Action, mods: Mods) void {
    if (action == glfw.Action.release) return;
    _ = window;

    var mod = @intToEnum(input.Modifiers, (mods.toInt(u8) & 0b111));
    const key_name = (glfw_key.getName(scancode));

    const key: input.Key = blk: {
        if (key_name) |kn| {
            const key_unicode = unicode.utf8Decode(kn) catch return;
            break :blk .{
                .key = .{ .code_point = key_unicode },
                .mod = mod,
            };
        } else if (isFunctionKey(glfw_key)) {
            break :blk .{
                .key = .{ .function_key = glfwFunctionKeyToEditorFunctionKey(glfw_key) },
                .mod = mod,
            };
        } else {
            return;
        }
    };

    input_layer.keyInput(key);
}

pub fn mouseCallback(window: glfw.Window, mb: glfw.MouseButton, a: glfw.Action, m: glfw.Mods) void {
    _ = mb;
    _ = m;
    _ = window;

    if (a == .press or a == .repeat) ui.state.mousedown = true else ui.state.mousedown = false;
}

fn isFunctionKey(key: glfw.Key) bool {
    // zig fmt: off
    return switch (key) {
        .space, .escape, .enter, .tab, .backspace, .insert, .delete, .right, .left, .down, .up, .page_up, .page_down, .home, .end, .caps_lock, .scroll_lock, .num_lock, .print_screen, .pause, .F1, .F2, .F3, .F4, .F5, .F6, .F7, .F8, .F9, .F10, .F11, .F12, .F13, .F14, .F15, .F16, .F17, .F18, .F19, .F20, .F21, .F22, .F23, .F24, .kp_enter
        => true,
        else => false,
    };
    // zig fmt: on
}

fn glfwFunctionKeyToEditorFunctionKey(key: glfw.Key) input.FunctionKey {
    // zig fmt: off
    return switch (key) {
        .unknown      => .unknown,
        .space        => .space,
        .escape       => .escape,
        .enter        => .enter,
        .tab          => .tab,
        .backspace    => .backspace,
        .insert       => .insert,
        .delete       => .delete,
        .right        => .right,
        .left         => .left,
        .down         => .down,
        .up           => .up,
        .page_up      => .page_up,
        .page_down    => .page_down,
        .home         => .home,
        .end          => .end,
        .caps_lock    => .caps_lock,
        .scroll_lock  => .scroll_lock,
        .num_lock     => .num_lock,
        .print_screen => .print_screen,
        .pause        => .pause,
        .F1           => .f1,
        .F2           => .f2,
        .F3           => .f3,
        .F4           => .f4,
        .F5           => .f5,
        .F6           => .f6,
        .F7           => .f7,
        .F8           => .f8,
        .F9           => .f9,
        .F10          => .f10,
        .F11          => .f11,
        .F12          => .f12,
        .F13          => .f13,
        .F14          => .f14,
        .F15          => .f15,
        .F16          => .f16,
        .F17          => .f17,
        .F18          => .f18,
        .F19          => .f19,
        .F20          => .f20,
        .F21          => .f21,
        .F22          => .f22,
        .F23          => .f23,
        .F24          => .f24,
        .kp_enter     => .kp_enter,

        else => .escape, // should be unreachable but just in case make it .escape
    };
    // zig fmt: on
}
