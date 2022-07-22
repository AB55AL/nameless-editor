const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;

const Buffer = @import("buffer.zig");
const file_io = @import("file_io.zig");

extern var global_allocator: std.mem.Allocator;
extern var global_buffers: ArrayList(*Buffer);

/// Returns a pointer to a buffer.
/// If a buffer with the given file_path already exists
/// returns a pointer to that buffer otherwise
/// creates a new buffer, adds it to the global_buffers array and
/// returns a pointer to it.
pub fn createBuffer(file_path: []const u8) !*Buffer {
    for (global_buffers.items) |buffer|
        if (eql(u8, file_path, buffer.file_path))
            return buffer;

    var buffer = try createLocalBuffer(file_path);
    try global_buffers.append(buffer);
    return buffer;
}

/// Opens a file and returns a pointer to a buffer.
/// Does not add the buffer to the global_buffers array
pub fn createLocalBuffer(file_path: []const u8) !*Buffer {
    const full_file_path = try file_io.fullFilePath(global_allocator, file_path);
    defer global_allocator.free(full_file_path);

    const file = try fs.cwd().openFile(full_file_path, .{});
    defer file.close();
    const metadata = try file.metadata();
    try file.seekTo(0);
    var buf = try file.readToEndAlloc(global_allocator, metadata.size());
    defer global_allocator.free(buf);

    var buffer = try global_allocator.create(Buffer);
    buffer.* = try Buffer.init(full_file_path, buf);

    return buffer;
}
