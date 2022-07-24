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
}

fn open(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBuffer(null, file_path) catch unreachable;
}
fn openRight(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferRight(null, file_path) catch unreachable;
}
fn openLeft(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferLeft(null, file_path) catch unreachable;
}
fn openAbove(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferAbove(null, file_path) catch unreachable;
}
fn openBelow(file_path: []const u8) void {
    if (file_path.len == 0) return;
    buffer_ops.openBufferBelow(null, file_path) catch unreachable;
}
