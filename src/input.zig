const std = @import("std");
const print = std.debug.print;

const freetype = @import("freetype");
const glfw = @import("glfw");
const Key = glfw.Key;
const Action = glfw.Action;
const Mods = glfw.Mods;

const Cursor = @import("cursor.zig");
const Buffer = @import("buffer.zig");
const history = @import("history.zig");

extern var font_size: i32;
extern var buffer: *Buffer;

pub fn characterInputCallback(window: glfw.Window, code_point: u21) void {
    _ = window;
    _ = code_point;
    switch (code_point) {
        0...127 => {
            var b = [_]u8{@intCast(u8, code_point)};
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
    if (action == Action.press or action == Action.repeat) {
        if (mods.control) {
            if (key == Key.z) history.undo(buffer) catch |err| {
                print("{}", .{err});
            };
            if (key == Key.y) history.redo(buffer) catch |err| {
                print("{}", .{err});
            };
        }
    }
    if (action == Action.press or action == Action.repeat) {
        switch (key) {
            Key.escape => {
                buffer.insert(buffer.cursor.row, buffer.cursor.col, "-HELLO\nTHERE\nMY\nFRIEND-") catch |err| {
                    print("{}\n", .{err});
                };
            },
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
                } else {
                    buffer.updateHistory() catch |err| {
                        print("{}", .{err});
                    };
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
    _ = scancode;
}
