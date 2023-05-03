const std = @import("std");
const print = @import("std").debug.print;

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const editor = @import("editor.zig");
const command_line = @import("command_line.zig");
const file_io = @import("file_io.zig");
const add = editor.addCommand;

const internal = globals.internal;

pub fn setDefaultCommands() !void {
    try add("o", open, "Open a buffer on the current window");
    try add("oe", openEast, "Open a buffer east of the current window");
    try add("ow", openWest, "Open a buffer west of the current window");
    try add("on", openNorth, "Open a buffer north of the current window");
    try add("os", openSouth, "Open a buffer south of the current window");

    try add("save", saveFocused, "Save the buffer");
    try add("saveAs", saveAsFocused, "Save the buffer as");
    try add("forceSave", forceSaveFocused, "Force the buffer to save");
    try add("close", closeFocused, "Closes the focused buffer window");
    try add("sq", saveAndQuitFocused, "Save and kill the focused buffer window");
    try add("forceSaveAndQuit", forceSaveAndQuitFocused, "Force save and kill the focused buffer window");

    try add("im.demo", imDemo, "Show imgui demo window");
    try add("ui.ins", bufferInspector, "Show the editor inspector");
}

fn imDemo(value: bool) void {
    globals.ui.imgui_demo = value;
}

fn bufferInspector(value: bool) void {
    globals.ui.inspect_editor = value;
}

fn open(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = editor.openBufferFP(file_path, .{}) catch |err| {
        print("open command: err={}\n", .{err});
    };
}
fn openEast(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = editor.openBufferFP(file_path, .{ .dir = .east }) catch |err| {
        print("openRight command: err={}\n", .{err});
    };
}
fn openWest(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = editor.openBufferFP(file_path, .{ .dir = .west }) catch |err| {
        print("openLeft command: err={}\n", .{err});
    };
}
fn openNorth(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = editor.openBufferFP(file_path, .{ .dir = .north }) catch |err| {
        print("openAbove command: err={}\n", .{err});
    };
}
fn openSouth(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = editor.openBufferFP(file_path, .{ .dir = .south }) catch |err| {
        print("openBelow command: err={}\n", .{err});
    };
}

fn saveFocused() void {
    var buffer = editor.focusedBufferHandle() orelse return;
    editor.saveBuffer(buffer, .{}) catch |err| {
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
    var bh = editor.focusedBufferAndHandle() orelse return;
    var buffer = bh.buffer;

    var fp: []const u8 = undefined;
    if (std.fs.path.isAbsolute(file_path)) {
        fp = file_path;
        buffer.setFilePath(fp) catch |err| {
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
        buffer.setFilePath(fp) catch |err| {
            print("err={}\n", .{err});
            return;
        };

        internal.allocator.free(fp);
    }

    editor.saveBuffer(bh.bhandle, .{}) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSave", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceSaveFocused() void {
    var bhandle = editor.focusedBufferHandle() orelse return;
    editor.saveBuffer(bhandle, .{ .force_save = true }) catch |err|
        print("err={}\n", .{err});
}

fn closeFocused() void {
    var bw = editor.focusedBW() orelse return;
    editor.closeBW(bw);
}

fn saveAndQuitFocused() void {
    var bw = editor.focusedBW() orelse return;

    editor.saveBuffer(bw.data.bhandle, .{}) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSaveAndQuit\n", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
    editor.closeBW(bw);
}

fn forceSaveAndQuitFocused() void {
    var bw = editor.focusedBW() orelse return;
    editor.saveBuffer(bw.data.bhandle, .{ .force_save = true }) catch |err| {
        print("err={}\n", .{err});
    };

    editor.closeBW(bw);
}
