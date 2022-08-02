const std = @import("std");
const print = std.debug.print;
const fs = std.fs;

const globals = @import("../globals.zig");
const internal = globals.internal;

const Buffer = @import("buffer.zig");

pub fn writeToFile(buffer: *Buffer) !void {
    const new_file_suffix = ".editor-new";
    const original_file_suffix = ".editor-original";

    const new_file_path = try std.mem.concat(internal.allocator, u8, &[_][]const u8{
        buffer.metadata.file_path,
        new_file_suffix,
    });
    defer internal.allocator.free(new_file_path);

    const original_tmp_file_path = try std.mem.concat(internal.allocator, u8, &[_][]const u8{
        buffer.metadata.file_path,
        original_file_suffix,
    });
    defer internal.allocator.free(original_tmp_file_path);

    const content_of_buffer = try buffer.lines.copy();
    defer internal.allocator.free(content_of_buffer);

    const file_dir = &(try fs.openDirAbsolute(fs.path.dirname(buffer.metadata.file_path).?, .{}));
    defer file_dir.close();

    const new_file = try fs.createFileAbsolute(new_file_path, .{});
    defer new_file.close();

    try new_file.writeAll(content_of_buffer);
    try std.os.rename(buffer.metadata.file_path, original_tmp_file_path);
    try std.os.rename(new_file_path, buffer.metadata.file_path);
    try file_dir.deleteFile(original_tmp_file_path);
}

pub fn fullFilePath(file_path: []const u8, out_buffer: []u8) !u16 {
    if (fs.path.isAbsolute(file_path)) {
        std.mem.copy(u8, out_buffer, file_path);
        return @intCast(u16, file_path.len);
    } else {
        const sep = fs.path.sep;
        var cwd_path = try std.os.getcwd(out_buffer);
        out_buffer[cwd_path.len] = sep;
        var out = out_buffer[cwd_path.len + 1 ..];
        for (file_path) |c, i|
            out[i] = c;

        return @intCast(u16, cwd_path.len + file_path.len + 1);
    }
}
