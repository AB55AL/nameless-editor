const std = @import("std");
const print = std.debug.print;

const freetype = @import("freetype");
const glfw = @import("glfw");
const Key = glfw.Key;
const Action = glfw.Action;
const Mods = glfw.Mods;

const Cursor = @import("cursor.zig");
const Buffer = @import("buffer.zig");

extern var font_size: i32;
extern var buffer: *Buffer;

pub fn characterInputCallback(window: glfw.Window, code_point: u21) void {
    _ = window;
    _ = code_point;
    // print("{}\n", .{code_point});
    switch (code_point) {
        0...127 => {
            var b = [_]u8{@intCast(u8, code_point)};
            // print("{s}\n", .{b});
            buffer.insert(buffer.cursor.row, buffer.cursor.col, b[0..]) catch |err| {
                print("{}", .{err});
            };
            buffer.moveCursorRelative(0, 1);
        },
        else => {
            print("Don't know the character ({})\n", .{code_point});
        },
    }
}

pub fn keyInputCallback(window: glfw.Window, key: Key, scancode: i32, action: Action, mods: Mods) void {
    _ = window;
    if (mods.control) {
        print("ctrl and {}\n", .{key});
    }
    if (action == Action.press or action == Action.repeat) {
        switch (key) {
            Key.escape => {
                print("normal mode :D\n", .{});
            },
            // Key.minus => {
            //     if (font_size <= 10) {
            //         font_size = 10;
            //         return;
            //     }
            //     font_size -= 1;
            //     face.setCharSize(60 * font_size, 0, 0, 0) catch |err| {
            //         print("{}\n", .{err});
            //     };
            //     txt.generateAndCacheFontTextures(face) catch |err| {
            //         print("{}\n", .{err});
            //     };
            // },
            Key.backspace => {
                if (buffer.cursor.col > 1) {
                    buffer.moveCursorRelative(0, -1);
                    buffer.delete(buffer.cursor.row, buffer.cursor.col, buffer.cursor.col + 1) catch |err| {
                        print("{}\n", .{err});
                    };
                }
            },
            Key.delete => {
                buffer.delete(buffer.cursor.row, buffer.cursor.col, buffer.cursor.col + 1) catch |err| {
                    print("{}\n", .{err});
                };
            },
            Key.F4 => {
                if (mods.alt) {
                    window.setShouldClose(true);
                }
            },
            Key.right => {
                buffer.moveCursorRelative(0, 1);
            },
            Key.left => {
                buffer.moveCursorRelative(0, -1);
            },
            Key.up => {
                buffer.moveCursorRelative(-1, 0);
            },
            Key.down => {
                buffer.moveCursorRelative(1, 0);
            },
            else => {
                // print("Don't know the key ({})\n", .{key});
            },
        }
    }
    // print("key {}\taction {}\tmod {}\ncode {}\n\n\n", .{ key, action, mods, scancode });
    _ = scancode;
}

// pub fn insertCodePoint(active_cursor: *Cursor, code_point: u21) void {
//     buf[active_cursor.row] = @intCast(u8, code_point);
//     active_cursor.moveToRelative(0, 1);
// }

// pub fn deleteCodePoint(active_buffer: *Buffer, backword: bool) void {
//     if (active_buffer.cursor.row <= 0) {
//         active_buffer.cursor.row = 1;
//         return;
//     }
//     if (backword) {
//         active_buffer.moveCursorRelative(-1, 0);
//     } else {
//         active_buffer.moveCursorRelative(1, 0);
//     }
//     var row = @intCast(usize, active_buffer.cursor.row);
//     buf[row] = ' ';
//     print("back\n", .{});
// }
