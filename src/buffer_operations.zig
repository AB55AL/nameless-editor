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

extern var global: Global;
extern var internal: GlobalInternal;

/// Returns a pointer to a buffer.
/// If a buffer with the given file_path already exists
/// returns a pointer to that buffer otherwise
/// creates a new buffer, adds it to the global.buffers array and
/// returns a pointer to it.
pub fn createBuffer(file_path: []const u8) !*Buffer {
    for (global.buffers.items) |buffer|
        if (eql(u8, file_path, buffer.file_path))
            return buffer;

    var buffer = try createLocalBuffer(file_path);
    try global.buffers.append(buffer);
    return buffer;
}

/// Opens a file and returns a pointer to a buffer.
/// Does not add the buffer to the global.buffers array
pub fn createLocalBuffer(file_path: []const u8) !*Buffer {
    const full_file_path = try file_io.fullFilePath(file_path);
    defer internal.allocator.free(full_file_path);

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
