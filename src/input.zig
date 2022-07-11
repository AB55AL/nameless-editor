const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;
const ArrayList = std.ArrayList;

const freetype = @import("freetype");
const glfw = @import("glfw");
const Mods = glfw.Mods;

const Cursor = @import("cursor.zig");
const Buffer = @import("buffer.zig");
const history = @import("history.zig");

const input_layer = @import("input_layer");

extern var font_size: i32;
extern var buffer: *Buffer;

var fixed_buffer: [64]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&fixed_buffer);
const fixed_allocator = fba.allocator();

pub fn characterInputCallback(window: glfw.Window, code_point: u21) void {
    _ = window;
    var utf8_bytes: [4]u8 = undefined;
    var bytes = unicode.utf8Encode(code_point, &utf8_bytes) catch unreachable;
    input_layer.characterInputCallback(utf8_bytes[0..bytes]);
}

pub fn keyInputCallback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: Mods) void {
    _ = window;
    if (action == glfw.Action.press or action == glfw.Action.repeat) {
        var mod = @intToEnum(Modifiers, (mods.toInt(u8) & 0b111));

        var key_name = (key.getName(scancode) catch unreachable);
        var key_value: []const u8 = undefined;
        if (key_name) |name| {
            key_value = std.mem.concat(fixed_allocator, u8, &[_][]const u8{
                modifierToString(mod),
                name,
            }) catch unreachable;
        } else if (functionKeyToString(key)) |function_key| {
            key_value = std.mem.concat(fixed_allocator, u8, &[_][]const u8{
                modifierToString(mod),
                function_key,
            }) catch unreachable;
        } else {
            return;
        }
        input_layer.keyInputCallback(key_value);
        fixed_allocator.free(key_value);
    }
}

fn functionKeyToString(key: glfw.Key) ?[]const u8 {
    return switch (key) {
        .space => "<SPACE>",
        .escape => "<ESCAPE>",
        .enter => "<ENTER>",
        .tab => "<TAB>",
        .backspace => "<BACKSPACE>",
        .insert => "<INSERT>",
        .delete => "<DELETE>",
        .right => "<RIGHT>",
        .left => "<LEFT>",
        .down => "<DOWN>",
        .up => "<UP>",
        .page_up => "<PAGE_UP>",
        .page_down => "<PAGE_DOWN>",
        .home => "<HOME>",
        .end => "<END>",
        .caps_lock => "<CAPS_LOCK>",
        .scroll_lock => "<SCROLL_LOCK>",
        .num_lock => "<NUM_LOCK>",
        .print_screen => "<PRINT_SCREEN>",
        .pause => "<PAUSE>",
        .F1 => "<F1>",
        .F2 => "<F2>",
        .F3 => "<F3>",
        .F4 => "<F4>",
        .F5 => "<F5>",
        .F6 => "<F6>",
        .F7 => "<F7>",
        .F8 => "<F8>",
        .F9 => "<F9>",
        .F10 => "<F10>",
        .F11 => "<F11>",
        .F12 => "<F12>",
        .F13 => "<F13>",
        .F14 => "<F14>",
        .F15 => "<F15>",
        .F16 => "<F16>",
        .F17 => "<F17>",
        .F18 => "<F18>",
        .F19 => "<F19>",
        .F20 => "<F20>",
        .F21 => "<F21>",
        .F22 => "<F22>",
        .F23 => "<F23>",
        .F24 => "<F24>",
        .kp_enter => "<KP_ENTER>",
        else => null,
        // blk: {
        //     // print("{}\n", .{key});
        //     break :blk "";
        // },
    };
}

fn modifierToString(mod: Modifiers) []const u8 {
    return switch (mod) {
        .none => "",
        .shift => "S_",
        .control => "C_",
        .control_shift => "C_S_",
        .alt => "A_",
        .alt_shift => "A_S_",
        .control_alt => "C_A_",
        .control_alt_shift => "C_S_A_",
    };
}

const Modifiers = enum(u3) {
    none = 0,
    shift = 1,
    control = 2,
    control_shift = 3,
    alt = 4,
    alt_shift = 5,
    control_alt = 6,
    control_alt_shift = 7,
};
