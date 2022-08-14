const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;
const assert = std.debug.assert;

const Buffer = @import("buffer.zig");
const file_io = @import("file_io.zig");
const globals = @import("../globals.zig");
const Windows = @import("../ui/window.zig").Windows;
const Window = @import("../ui/window.zig").Window;
const window_ops = @import("../ui/window_ops.zig");

const global = globals.global;
const internal = globals.internal;

pub const Error = error{
    SavingPathlessBuffer,
    SavingNullBuffer,
    KillingNullBuffer,
    KillingDirtyBuffer,
};

/// Returns a pointer to a buffer.
/// If a buffer with the given file_path already exists
/// returns a pointer to that buffer otherwise
/// creates a new buffer, adds it to the global.buffers array and
/// returns a pointer to it.
pub fn createBuffer(file_path: []const u8) !*Buffer {
    var buf = try getBufferFP(file_path);
    if (buf) |b| return b;

    var buffer = try createLocalBuffer(file_path);
    try global.buffers.append(buffer);
    return buffer;
}

/// Opens a file and returns a pointer to a buffer.
/// Does not add the buffer to the global.buffers array
/// Always creates a new buffer
pub fn createLocalBuffer(file_path: []const u8) !*Buffer {
    var out_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    const full_file_path = try file_io.fullFilePath(file_path, &out_buffer);

    const file = try fs.cwd().openFile(full_file_path, .{});
    defer file.close();
    const metadata = try file.metadata();
    try file.seekTo(0);
    var buf = try file.readToEndAlloc(internal.allocator, metadata.size());
    defer internal.allocator.free(buf);

    var buffer = try internal.allocator.create(Buffer);
    buffer.* = try Buffer.init(internal.allocator, full_file_path, buf);
    buffer.metadata.file_last_mod_time = metadata.modified();

    return buffer;
}

/// Given an *index* searches the global.buffers array for a buffer
/// matching either.
/// Returns null if the buffer isn't found.
pub fn getBufferI(index: u32) !?*Buffer {
    for (global.buffers.items) |buffer| {
        if (buffer.index.? == index)
            return buffer;
    }
    return null;
}

pub fn getOrCreateBuffer(index: ?u32, file_path: []const u8) !*Buffer {
    var buffer: *Buffer = undefined;
    if (index) |i|
        buffer = (try getBufferI(i)) orelse
            try getBufferFP(file_path) orelse
            try createBuffer(file_path)
    else
        buffer = (try getBufferFP(file_path)) orelse
            try createBuffer(file_path);

    return buffer;
}

/// Given an *file_path* searches the global.buffers array for a buffer
/// matching either.
/// Returns null if the buffer isn't found.
pub fn getBufferFP(file_path: []const u8) !?*Buffer {
    for (global.buffers.items) |buffer| {
        var out_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
        const full_fp = try file_io.fullFilePath(file_path, &out_buffer);
        if (eql(u8, full_fp, buffer.metadata.file_path))
            return buffer;
    }
    return null;
}

pub fn openBufferI(index: u32, direction: window_ops.Direction) !void {
    var buffer: *Buffer = (try getBufferI(index)) orelse return;

    if (direction == .here and global.windows.wins.items.len > 0) {
        global.windows.focusedWindow().buffer = buffer;
        global.focused_buffer = buffer;
    } else {
        var window = try global.windows.openWindow(if (direction == .here) .next else direction);
        window.buffer = buffer;
        global.focused_buffer = buffer;
    }
}

pub fn openBufferFP(file_path: []const u8, direction: window_ops.Direction) !void {
    var buffer: *Buffer = try getOrCreateBuffer(null, file_path);

    if (direction == .here and global.windows.wins.items.len > 0) {
        global.windows.focusedWindow().buffer = buffer;
        global.focused_buffer = buffer;
    } else {
        var window = try global.windows.openWindow(if (direction == .here) .next else direction);
        window.buffer = buffer;
        global.focused_buffer = buffer;
    }
}

pub fn saveBuffer(buffer: *Buffer, force_write: bool) !void {
    if (buffer.metadata.file_path.len == 0)
        return error.SavingPathlessBuffer;
    if (buffer.index == null)
        return error.SavingNullBuffer;

    try file_io.writeToFile(buffer, force_write);
    buffer.metadata.dirty = false;
}

/// Deinits the buffer and closes it's window.
/// To only deinit use `Buffer.deinitAndTrash()`
pub fn killBuffer(buffer: *Buffer) !void {
    if (buffer.index == null)
        return error.KillingNullBuffer;

    if (buffer.metadata.dirty)
        return error.KillingDirtyBuffer;

    try forceKillBuffer(buffer);
}

pub fn forceKillBuffer(buffer: *Buffer) !void {
    if (buffer.index == null)
        return error.KillingNullBuffer;

    window_ops.closeBufferWindow(buffer);
    buffer.deinitAndTrash();
    if (global.buffers.items.len > 0)
        global.focused_buffer = global.buffers.items[0];
}

pub fn saveAndQuit(buffer: *Buffer, force_write: bool) !void {
    try saveBuffer(buffer, force_write);
    try killBuffer(buffer);
}
