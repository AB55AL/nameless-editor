const std = @import("std");
const print = std.debug.print;
const fs = std.fs;

const GlobalInternal = @import("global_types.zig").GlobalInternal;
extern var internal: GlobalInternal;

const Buffer = @import("buffer.zig");

pub fn writeToFile(buffer: *Buffer) !void {
    const new_file_suffix = ".editor-new";
    const original_file_suffix = ".editor-original";

    const new_file_path = try std.mem.concat(internal.allocator, u8, &[_][]const u8{
        buffer.file_path,
        new_file_suffix,
    });
    defer internal.allocator.free(new_file_path);

    const original_tmp_file_path = try std.mem.concat(internal.allocator, u8, &[_][]const u8{
        buffer.file_path,
        original_file_suffix,
    });
    defer internal.allocator.free(original_tmp_file_path);

    const content_of_buffer = try buffer.lines.copy();
    defer internal.allocator.free(content_of_buffer);

    const file_dir = &(try fs.openDirAbsolute(fs.path.dirname(buffer.file_path).?, .{}));
    defer file_dir.close();

    const new_file = try fs.createFileAbsolute(new_file_path, .{});
    defer new_file.close();

    try new_file.writeAll(content_of_buffer);
    try std.os.rename(buffer.file_path, original_tmp_file_path);
    try std.os.rename(new_file_path, buffer.file_path);
    try file_dir.deleteFile(original_tmp_file_path);
}

pub fn fullFilePath(file_path: []const u8) ![]const u8 {
    var full_file_path: []u8 = undefined;

    if (fs.path.isAbsolute(file_path)) {
        full_file_path = try internal.allocator.alloc(u8, file_path.len);
        std.mem.copy(u8, full_file_path, file_path);
    } else {
        var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var cwd_path = try std.os.getcwd(&buf);
        full_file_path = try fs.path.join(internal.allocator, &[_][]const u8{
            cwd_path,
            file_path,
        });
    }

    return full_file_path;
}
