const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const fs = std.fs;

const core = @import("core");
const Cursor = core.Cursor;
const layouts = @import("../../../plugins/layouts.zig");

const global = core.global;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var allocator: std.mem.Allocator = undefined;
var mappings: std.StringHashMap(*const fn () void) = undefined;
var log_file: fs.File = undefined;

pub fn inputLayerInit() !void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = gpa.allocator();
    mappings = std.StringHashMap(*const fn () void).init(allocator);

    const data_path = std.os.getenv("XDG_DATA_HOME").?;
    const log_path = try std.mem.concat(allocator, u8, &.{ data_path, "/ne" });
    defer allocator.free(log_path);
    var dir = try fs.openDirAbsolute(log_path, .{});
    defer dir.close();

    log_file = try (dir.openFile("input-log", .{ .mode = .write_only }) catch |err| if (err == fs.Dir.OpenError.FileNotFound)
        dir.createFile("input-log", .{})
    else
        err);

    setDefaultMappnigs();
    const end = log_file.getEndPos() catch return;
    _ = log_file.pwrite("\n---------------new editor instance---------------\n", end) catch |err| print("err={}", .{err});
}

pub fn inputLayerDeinit() void {
    mappings.deinit();
    log_file.close();
    _ = gpa.deinit();
}

pub fn keyInput(key: []const u8) void {
    if (mappings.get(key)) |f| {
        f();
        const end = log_file.getEndPos() catch return;
        _ = log_file.pwrite(key, end) catch |err| print("err={}", .{err});
        _ = log_file.pwrite("\n", end + key.len) catch |err| print("err={}", .{err});
    }
}

pub fn characterInput(utf8_seq: []const u8) void {
    global.focused_buffer.insertBeforeCursor(utf8_seq) catch |err| {
        print("input_layer.characterInputCallback()\n\t{}\n", .{err});
    };

    Cursor.moveRelative(global.focused_buffer, 0, 1);

    const end = log_file.getEndPos() catch return;
    const insert = "insert:";
    _ = log_file.pwrite(insert, end) catch |err| print("err={}", .{err});
    _ = log_file.pwrite(utf8_seq, end + insert.len) catch |err| print("err={}", .{err});
    _ = log_file.pwrite("\n", end + insert.len + utf8_seq.len) catch |err| print("err={}", .{err});
}

pub fn map(key: []const u8, function: *const fn () void) void {
    mappings.put(key, function) catch |err| {
        print("input_layer.map()\n\t{}\n", .{err});
    };
}

fn setDefaultMappnigs() void {
    map("<F2>", insertAlot);
    map("<F3>", cycleThroughWindowsNext);
    map("S_<F3>", cycleThroughWindowsPrev);

    map("<BACKSPACE>", deleteBackward);
    map("<DELETE>", deleteForward);

    map("<RIGHT>", moveRight);
    map("<LEFT>", moveLeft);
    map("<UP>", moveUp);
    map("<DOWN>", moveDown);

    map("C_<RIGHT>", focusRightWindow);
    map("C_<LEFT>", focusLeftWindow);
    map("C_<UP>", focusAboveWindow);
    map("C_<DOWN>", focusBelowWindow);

    map("<ENTER>", enterKey);
    map("C_c", toggleCommandLine);
}

fn deleteBackward() void {
    if (global.focused_buffer.cursor.col > 1) {
        global.focused_buffer.deleteBeforeCursor(1) catch |err| {
            print("input_layer.deleteBackward()\n\t{}\n", .{err});
        };
    }
}

fn deleteForward() void {
    global.focused_buffer.deleteAfterCursor(1) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}
fn moveRight() void {
    Cursor.moveRelative(global.focused_buffer, 0, 1);
}
fn moveLeft() void {
    Cursor.moveRelative(global.focused_buffer, 0, -1);
}
fn moveUp() void {
    Cursor.moveRelative(global.focused_buffer, -1, 0);
}
fn moveDown() void {
    Cursor.moveRelative(global.focused_buffer, 1, 0);
}

fn focusRightWindow() void {
    core.global.windows.changeFocusedWindow(.right);
}
fn focusLeftWindow() void {
    core.global.windows.changeFocusedWindow(.left);
}
fn focusAboveWindow() void {
    core.global.windows.changeFocusedWindow(.above);
}
fn focusBelowWindow() void {
    core.global.windows.changeFocusedWindow(.below);
}

fn toggleCommandLine() void {
    if (global.command_line_is_open.*)
        core.command_line.close()
    else
        core.command_line.open();
}

fn enterKey() void {
    if (global.command_line_is_open.*)
        core.command_line.run() catch |err| {
            print("Couldn't run command. err={}\n", .{err});
        }
    else
        insertNewLineAtCursor();
}

fn insertNewLineAtCursor() void {
    global.focused_buffer.insertBeforeCursor("\n") catch |err| {
        print("input_layer.insertNewLineAtCursor()\n\t{}\n", .{err});
    };
    Cursor.moveRelative(global.focused_buffer, 1, 0);
    Cursor.moveToStartOfLine(global.focused_buffer);
}

fn insertAlot() void {
    // global.focused_buffer.deleteRows(1, 3) catch unreachable;
    global.focused_buffer.insertBeforeCursor("شششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششش") catch unreachable;
}

fn cycleThroughWindowsNext() void {
    core.global.windows.cycleThroughWindows(.next);
}
fn cycleThroughWindowsPrev() void {
    core.global.windows.cycleThroughWindows(.prev);
}
