const std = @import("std");
const print = @import("std").debug.print;

const GlobalInternal = @import("global_types.zig").GlobalInternal;
const Global = @import("global_types.zig").Global;
const Buffer = @import("buffer.zig");
const Cursor = @import("cursor.zig");
const buffer_ops = @import("buffer_operations.zig");
const command_line = @import("command_line.zig");
const addCommand = command_line.addCommand;

extern var internal: GlobalInternal;
extern var global: Global;

pub fn setDefaultCommands() !void {
    try addCommand("open", open);
    try addCommand("openRight", openRight);
    try addCommand("openLeft", openLeft);
    try addCommand("openAbove", openAbove);
    try addCommand("openBelow", openBelow);
    try addCommand("save", save);
}

fn open(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBuffer(null, file_path, .here) catch |err| {
        print("open command: err={}\n", .{err});
    };
}
fn openRight(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBuffer(null, file_path, .right) catch |err| {
        print("openRight command: err={}\n", .{err});
    };
}
fn openLeft(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBuffer(null, file_path, .left) catch |err| {
        print("openLeft command: err={}\n", .{err});
    };
}
fn openAbove(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBuffer(null, file_path, .above) catch |err| {
        print("openAbove command: err={}\n", .{err});
    };
}
fn openBelow(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBuffer(null, file_path, .below) catch |err| {
        print("openBelow command: err={}\n", .{err});
    };
}

// FIXME: after fixing the command line change this to not take any args
fn save(ignore: []const u8) void {
    _ = ignore;
    buffer_ops.saveBuffer(global.focused_buffer) catch unreachable;
}
