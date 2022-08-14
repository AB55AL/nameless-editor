const std = @import("std");
const print = @import("std").debug.print;

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const Cursor = @import("cursor.zig");
const buffer_ops = @import("buffer_ops.zig");
const window_ops = @import("../ui/window_ops.zig");
const command_line = @import("command_line.zig");
const file_io = @import("file_io.zig");
const add = command_line.add;

const global = globals.global;
const internal = globals.internal;

pub fn setDefaultCommands() !void {
    try add("open", open);
    try add("openRight", openRight);
    try add("openLeft", openLeft);
    try add("openAbove", openAbove);
    try add("openBelow", openBelow);

    try add("closeWindow", window_ops.closeFocusedWindow);

    try add("save", saveFocused);
    try add("forceSave", forceSaveFocused);
    try add("kill", killFocused);
    try add("forceKill", forceKillFocused);
    try add("saveAndQuit", saveAndQuitFocused);
    try add("forceSaveAndQuit", forceSaveAndQuitFocused);

    try add("hResize", hResizeFocusedDown);
    try add("vResize", vResizeFocused);
    try add("eql", equalize);
}

fn open(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferFP(file_path, .here) catch |err| {
        print("open command: err={}\n", .{err});
    };
}
fn openRight(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferFP(file_path, .right) catch |err| {
        print("openRight command: err={}\n", .{err});
    };
}
fn openLeft(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferFP(file_path, .left) catch |err| {
        print("openLeft command: err={}\n", .{err});
    };
}
fn openAbove(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferFP(file_path, .above) catch |err| {
        print("openAbove command: err={}\n", .{err});
    };
}
fn openBelow(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferFP(file_path, .below) catch |err| {
        print("openBelow command: err={}\n", .{err});
    };
}

fn saveFocused() void {
    buffer_ops.saveBuffer(global.focused_buffer, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSave", .{});
        } else {
            print("{}\nerr={}\n", .{ @src(), err });
        }
    };
}

fn forceSaveFocused() void {
    buffer_ops.saveBuffer(global.focused_buffer, true) catch |err|
        print("{}\nerr={}\n", .{ @src(), err });
}

fn killFocused() void {
    buffer_ops.killBuffer(global.focused_buffer) catch |err| {
        if (err == buffer_ops.Error.KillingDirtyBuffer) {
            print("Cannot kill dirty buffer. Save the buffer or use forceKill", .{});
        } else {
            print("{}\nerr={}\n", .{ @src(), err });
        }
    };
}

fn forceKillFocused() void {
    buffer_ops.forceKillBuffer(global.focused_buffer) catch |err|
        print("{}\nerr={}\n", .{ @src(), err });
}

fn saveAndQuitFocused() void {
    buffer_ops.saveAndQuit(global.focused_buffer, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSaveAndQuit", .{});
        } else {
            print("{}\nerr={}\n", .{ @src(), err });
        }
    };
}

fn forceSaveAndQuitFocused() void {
    buffer_ops.saveAndQuit(global.focused_buffer, true) catch |err|
        print("{}\nerr={}\n", .{ @src(), err });
}

fn vResizeFocused(resize_value: f32) void {
    var win = global.windows.focusedWindow();
    global.windows.resize(win.index, resize_value, .right);
}

fn hResizeFocusedDown(resize_value: f32) void {
    var win = global.windows.focusedWindow();
    global.windows.resize(win.index, resize_value, .above);
}

fn equalize() void {
    global.windows.equalize();
}
