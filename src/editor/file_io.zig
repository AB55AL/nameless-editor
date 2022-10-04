const std = @import("std");
const print = std.debug.print;
const fs = std.fs;

const globals = @import("../globals.zig");
const internal = globals.internal;

const Buffer = @import("buffer.zig");

pub const Error = error{
    DifferentModTimes,
};

pub fn writeToFile(buffer: *Buffer, force_write: bool) !void {
    const new_file_suffix = ".editor-new";
    const original_file_suffix = ".editor-original";

    const new_file_path = try std.mem.concat(internal.allocator, u8, &.{
        buffer.metadata.file_path,
        new_file_suffix,
    });
    defer internal.allocator.free(new_file_path);

    const original_tmp_file_path = try std.mem.concat(internal.allocator, u8, &.{
        buffer.metadata.file_path,
        original_file_suffix,
    });
    defer internal.allocator.free(original_tmp_file_path);

    var file_dir = try fs.openDirAbsolute(fs.path.dirname(buffer.metadata.file_path).?, .{});
    defer file_dir.close();

    if (!force_write) {
        var stat = try file_dir.statFile(buffer.metadata.file_path);
        if (stat.mtime != buffer.metadata.file_last_mod_time)
            return Error.DifferentModTimes;
    }

    const new_file = try fs.createFileAbsolute(new_file_path, .{});
    defer new_file.close();

    const content_of_buffer = try buffer.lines.copy();
    defer internal.allocator.free(content_of_buffer);

    try new_file.writeAll(content_of_buffer);
    try std.os.rename(buffer.metadata.file_path, original_tmp_file_path);
    try std.os.rename(new_file_path, buffer.metadata.file_path);
    try file_dir.deleteFile(original_tmp_file_path);
}

pub fn fullFilePath(file_path: []const u8, out_buffer: []u8) ![]u8 {
    return fs.cwd().realpath(file_path, out_buffer);
}
