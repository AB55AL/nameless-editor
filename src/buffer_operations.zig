const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;

const Buffer = @import("buffer.zig");
const file_io = @import("file_io.zig");

extern var global_allocator: std.mem.Allocator;
extern var global_buffers: ArrayList(Buffer);

pub fn createBuffer(file_path: []const u8) !void {
    try global_buffers.append(try createLocalBuffer(file_path));
}

/// Opens a file and returns a copy of a buffer. Does not add the buffer
/// to the global_buffers array
pub fn createLocalBuffer(file_path: []const u8) !Buffer {
    const full_file_path = try file_io.fullFilePath(global_allocator, file_path);
    defer global_allocator.free(full_file_path);

    const file = try fs.cwd().openFile(full_file_path, .{});
    defer file.close();
    const metadata = try file.metadata();
    try file.seekTo(0);
    var buf = try file.readToEndAlloc(global_allocator, metadata.size());
    defer global_allocator.free(buf);

    return Buffer.init(full_file_path, buf);
}
