const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;

const Buffer = @import("buffer.zig");
const file_io = @import("file_io.zig");
const global_types = @import("global_types.zig");
const Global = global_types.Global;
const GlobalInternal = global_types.GlobalInternal;
const Windows = @import("ui/window.zig").Windows;

extern var global: Global;
extern var internal: GlobalInternal;

pub const Direction = enum(u3) {
    here,
    right,
    left,
    above,
    below,
};

/// Returns a pointer to a buffer.
/// If a buffer with the given file_path already exists
/// returns a pointer to that buffer otherwise
/// creates a new buffer, adds it to the global.buffers array and
/// returns a pointer to it.
pub fn createBuffer(file_path: []const u8) !*Buffer {
    var buf = try getBuffer(null, file_path);
    if (buf) |b| return b;

    var buffer = try createLocalBuffer(file_path);
    try global.buffers.append(buffer);
    return buffer;
}

/// Opens a file and returns a pointer to a buffer.
/// Does not add the buffer to the global.buffers array
pub fn createLocalBuffer(file_path: []const u8) !*Buffer {
    var out_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    const bytes = try file_io.fullFilePath(file_path, &out_buffer);
    const full_file_path = out_buffer[0..bytes];

    const file = try fs.cwd().openFile(full_file_path, .{});
    defer file.close();
    const metadata = try file.metadata();
    try file.seekTo(0);
    var buf = try file.readToEndAlloc(internal.allocator, metadata.size());
    defer internal.allocator.free(buf);

    var buffer = try internal.allocator.create(Buffer);
    buffer.* = try Buffer.init(full_file_path, buf);

    return buffer;
}

/// Given an *index* or a *file_path* searches the global.buffers array for a buffer
/// matching either.
/// Returns null if the buffer isn't found or if both index and file_path are null
pub fn getBuffer(index: ?u32, file_path: ?[]const u8) !?*Buffer {
    for (global.buffers.items) |buffer| {
        if (index) |i|
            if (buffer.index.? == i)
                return buffer;

        if (file_path) |fp| {
            var out_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
            const bytes = try file_io.fullFilePath(fp, &out_buffer);
            const full_fp = out_buffer[0..bytes];
            if (eql(u8, full_fp, buffer.file_path)) {
                return buffer;
            }
        }
    }
    return null;
}

pub fn openBuffer(index: ?u32, file_path: ?[]const u8, direction: Direction) !void {
    var buffer = try getBuffer(index, file_path);
    const createWindow = switch (direction) {
        .here => Windows.changeCurrentWindow,
        .right => Windows.createRight,
        .left => Windows.createLeft,
        .above => Windows.createAbove,
        .below => Windows.createBelow,
    };
    var windows = &internal.windows;
    if (buffer) |buf| {
        try createWindow(windows, buf);
        global.focused_buffer = buf;
    } else if (file_path) |fp| {
        var buf = try createBuffer(fp);

        if (internal.windows.wins.items.len == 0) {
            try internal.windows.createNew(buf);
            global.focused_buffer = buf;
            internal.windows.focusedWindow().buffer = buf;
        } else {
            try createWindow(windows, buf);
        }

        global.focused_buffer = buf;
    } else {
        return error.CannotFindBuffer;
    }
}
pub fn saveBuffer(buffer: *Buffer) !void {
    if (buffer.file_path.len == 0) {
        print("can't save nameless buffer. use saveAs\n", .{});
        return;
    }
    try file_io.writeToFile(buffer);
}
