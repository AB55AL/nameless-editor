const std = @import("std");
const print = @import("std").debug.print;

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const buffer_ops = @import("buffer_ops.zig");
const command_line = @import("command_line.zig");
const file_io = @import("file_io.zig");
const add = command_line.add;

const global = globals.global;
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
    buffer_ops.saveBuffer(global.focused_buffer, false) catch |err| {
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

    var fp: []const u8 = undefined;
    if (std.fs.path.isAbsolute(file_path)) {
        fp = file_path;
        global.focused_buffer.metadata.setFilePath(fp) catch |err| {
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
        global.focused_buffer.metadata.setFilePath(fp) catch |err| {
            print("err={}\n", .{err});
            return;
        };

        internal.allocator.free(fp);
    }

    buffer_ops.saveBuffer(global.focused_buffer, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSave", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceSaveFocused() void {
    buffer_ops.saveBuffer(global.focused_buffer, true) catch |err|
        print("err={}\n", .{err});
}

fn killFocused() void {
    buffer_ops.killBuffer(global.focused_buffer) catch |err| {
        if (err == buffer_ops.Error.KillingDirtyBuffer) {
            print("Cannot kill dirty buffer. Save the buffer or use forceKill", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceKillFocused() void {
    buffer_ops.forceKillBuffer(global.focused_buffer) catch |err|
        print("err={}\n", .{err});
}

fn saveAndQuitFocused() void {
    buffer_ops.saveAndQuit(global.focused_buffer, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSaveAndQuit", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceSaveAndQuitFocused() void {
    buffer_ops.saveAndQuit(global.focused_buffer, true) catch |err|
        print("err={}\n", .{err});
}
