const std = @import("std");
const print = @import("std").debug.print;

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const buffer_ops = @import("buffer_ops.zig");
const command_line = @import("command_line.zig");
const file_io = @import("file_io.zig");
const add = command_line.add;

const editor = globals.editor;
const internal = globals.internal;

pub fn setDefaultCommands() !void {
    try add("o", open);
    try add("or", openRight);
    try add("ol", openLeft);
    try add("oa", openAbove);
    try add("ob", openBelow);

    try add("save", saveFocused);
    try add("saveAs", saveAsFocused);
    try add("forceSave", forceSaveFocused);
    try add("kill", killFocused);
    try add("forceKill", forceKillFocused);
    try add("sq", saveAndQuitFocused);
    try add("forceSaveAndQuit", forceSaveAndQuitFocused);
}

fn open(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path) catch |err| {
        print("open command: err={}\n", .{err});
    };
}
fn openRight(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path) catch |err| {
        print("openRight command: err={}\n", .{err});
    };
}
fn openLeft(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path) catch |err| {
        print("openLeft command: err={}\n", .{err});
    };
}
fn openAbove(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path) catch |err| {
        print("openAbove command: err={}\n", .{err});
    };
}
fn openBelow(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path) catch |err| {
        print("openBelow command: err={}\n", .{err});
    };
}

fn saveFocused() void {
    var fb = editor.focused_buffer orelse return;
    buffer_ops.saveBuffer(fb, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSave", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn saveAsFocused(file_path: []const u8) void {
    if (file_path.len == 0) return;
    var fb = editor.focused_buffer orelse return;

    var fp: []const u8 = undefined;
    if (std.fs.path.isAbsolute(file_path)) {
        fp = file_path;
        fb.metadata.setFilePath(fp) catch |err| {
            print("err={}\n", .{err});
            return;
        };
    } else {
        var array: [4000]u8 = undefined;
        var cwd = std.os.getcwd(&array) catch |err| {
            print("err={}\n", .{err});
            return;
        };
        fp = std.mem.concat(internal.allocator, u8, &.{
            cwd,
            &.{std.fs.path.sep},
            file_path,
        }) catch |err| {
            print("err={}\n", .{err});
            return;
        };
        fb.metadata.setFilePath(fp) catch |err| {
            print("err={}\n", .{err});
            return;
        };

        internal.allocator.free(fp);
    }

    buffer_ops.saveBuffer(fb, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSave", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceSaveFocused() void {
    var fb = editor.focused_buffer orelse return;
    buffer_ops.saveBuffer(fb, true) catch |err|
        print("err={}\n", .{err});
}

fn killFocused() void {
    var fb = editor.focused_buffer orelse return;
    buffer_ops.killBuffer(fb) catch |err| {
        if (err == buffer_ops.Error.KillingDirtyBuffer) {
            print("Cannot kill dirty buffer. Save the buffer or use forceKill", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceKillFocused() void {
    var fb = editor.focused_buffer orelse return;
    buffer_ops.forceKillBuffer(fb) catch |err|
        print("err={}\n", .{err});
}

fn saveAndQuitFocused() void {
    var fb = editor.focused_buffer orelse return;
    buffer_ops.saveAndQuit(fb, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSaveAndQuit", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceSaveAndQuitFocused() void {
    var fb = editor.focused_buffer orelse return;
    buffer_ops.saveAndQuit(fb, true) catch |err|
        print("err={}\n", .{err});
}
