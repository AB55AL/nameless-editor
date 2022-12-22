const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;
const assert = std.debug.assert;
const Buffer = @import("buffer.zig");
const file_io = @import("file_io.zig");
const globals = @import("../globals.zig");

const editor = globals.editor;
const internal = globals.internal;

pub const Error = error{
    SavingPathlessBuffer,
    SavingInvalidBuffer,
    KillingInvalidBuffer,
    KillingDirtyBuffer,
};

/// Returns a pointer to a buffer.
/// If a buffer with the given file_path already exists
/// returns a pointer to that buffer otherwise
/// creates a new buffer, adds it to the editor.buffers array and
/// returns a pointer to it.
pub fn createBuffer(file_path: []const u8) !*Buffer {
    if (file_path.len > 0) {
        var buf = try getBufferFP(file_path);
        if (buf) |b| return b;
    }

    var buffer = try createLocalBuffer(file_path);

    // Prepend to linked list
    buffer.next_buffer = editor.first_buffer;
    editor.first_buffer = buffer;
    editor.valid_buffers_count += 1;

    return buffer;
}

/// Opens a file and returns a pointer to a buffer.
/// Does not add the buffer to the editor.buffers array
/// Always creates a new buffer
pub fn createLocalBuffer(file_path: []const u8) !*Buffer {
    var buffer = try internal.allocator.create(Buffer);
    errdefer internal.allocator.destroy(buffer);

    if (file_path.len > 0) {
        var out_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
        const full_file_path = try file_io.fullFilePath(file_path, &out_buffer);

        const file = try fs.cwd().openFile(full_file_path, .{});
        defer file.close();
        const metadata = try file.metadata();
        try file.seekTo(0);
        var buf = try file.readToEndAlloc(internal.allocator, metadata.size());
        defer internal.allocator.free(buf);

        buffer.* = try Buffer.init(internal.allocator, full_file_path, buf);
        buffer.metadata.file_last_mod_time = metadata.modified();
    } else {
        buffer.* = try Buffer.init(internal.allocator, "", "");
    }

    return buffer;
}

pub fn createPathLessBuffer() !*Buffer {
    var buffer = try internal.allocator.create(Buffer);
    buffer.* = try Buffer.init(globals.internal.allocator, "", "");

    // Prepend to linked list
    buffer.next_buffer = editor.first_buffer;
    editor.first_buffer = buffer;
    editor.valid_buffers_count += 1;

    return buffer;
}

/// Given an *index* searches the editor.buffers array for a buffer
/// matching either.
/// Returns null if the buffer isn't found.
pub fn getBufferI(index: u32) ?*Buffer {
    if (editor.first_buffer == null) return null;

    var buffer = editor.first_buffer.?;
    while (true) {
        if (buffer.state == .valid and buffer.index == index) {
            return buffer;
        } else if (buffer.next_buffer) |nb| {
            buffer = nb;
        } else {
            return null;
        }
    }
}

fn getOrCreateBuffer(index: ?u32, file_path: []const u8) !*Buffer {
    var buffer: *Buffer = undefined;
    if (index) |i|
        buffer = getBufferI(i) orelse
            try getBufferFP(file_path) orelse
            try createBuffer(file_path)
    else
        buffer = (try getBufferFP(file_path)) orelse
            try createBuffer(file_path);

    return buffer;
}

/// Given an *file_path* searches the editor.buffers array for a buffer
/// matching either.
/// Returns null if the buffer isn't found.
pub fn getBufferFP(file_path: []const u8) !?*Buffer {
    if (editor.first_buffer == null) return null;

    var buffer = editor.first_buffer.?;
    var out_path_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    while (true) {
        const full_fp = try file_io.fullFilePath(file_path, &out_path_buffer);
        if (eql(u8, full_fp, buffer.metadata.file_path)) {
            return buffer;
        } else if (buffer.next_buffer) |nb| {
            buffer = nb;
        } else {
            return null;
        }
    }
}

pub fn openBufferI(index: u32) !*Buffer {
    var buffer: *Buffer = try getOrCreateBuffer(index, "");
    editor.previous_buffer_index = editor.focused_buffer.index;
    editor.focused_buffer = buffer;
    return buffer;
}

pub fn openBufferFP(file_path: []const u8) !*Buffer {
    var buffer: *Buffer = try getOrCreateBuffer(null, file_path);
    editor.previous_buffer_index = editor.focused_buffer.index;
    editor.focused_buffer = buffer;
    return buffer;
}

pub fn saveBuffer(buffer: *Buffer, force_write: bool) !void {
    if (buffer.metadata.file_path.len == 0)
        return Error.SavingPathlessBuffer;
    if (buffer.state == .invalid)
        return Error.SavingInvalidBuffer;

    try file_io.writeToFile(buffer, force_write);
    buffer.metadata.dirty = false;
}

/// Deinits the buffer and closes it's window.
/// To only deinit see `Buffer.deinitNoDestroy()` or `Buffer.deinitAndDestroy()`
pub fn killBuffer(buffer: *Buffer) !void {
    if (buffer.state == .invalid)
        return Error.KillingInvalidBuffer;

    if (buffer.metadata.dirty)
        return Error.KillingDirtyBuffer;

    try forceKillBuffer(buffer);
}

pub fn forceKillBuffer(buffer: *Buffer) !void {
    if (buffer.state == .invalid)
        return Error.KillingInvalidBuffer;

    buffer.deinitNoDestroy(internal.allocator);
    if (editor.valid_buffers_count > 0) {
        editor.focused_buffer = first_valid_buffer: {
            if (editor.first_buffer.?.state == .valid)
                break :first_valid_buffer editor.first_buffer.?
            else while (editor.first_buffer.?.next_buffer) |nb|
                if (nb.state == .valid)
                    break :first_valid_buffer nb;
        };
    }

    editor.valid_buffers_count -= 1;
}

pub fn saveAndQuit(buffer: *Buffer, force_write: bool) !void {
    try saveBuffer(buffer, force_write);
    try killBuffer(buffer);
}
