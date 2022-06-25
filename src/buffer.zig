const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;

const Cursor = @import("cursor.zig");
const GapBuffer = @import("GapBuffer.zig");
const shaders = @import("shaders.zig");

extern var cursor_shader: shaders.Shader;

const Buffer = @This();

cursor: Cursor,
content: ArrayList(GapBuffer),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, file_name: []const u8) !*Buffer {
    var buffer = try allocator.create(Buffer);
    buffer.content = ArrayList(GapBuffer).init(allocator);
    buffer.cursor = Cursor.init(cursor_shader);
    buffer.allocator = allocator;

    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();
    const metadata = try file.metadata();
    try file.seekTo(0);
    var buf = try file.readToEndAlloc(allocator, metadata.size());
    defer allocator.free(buf);

    var start: usize = 0;
    var end: usize = 0;
    for (buf) |char| {
        if (char == '\n') {
            const s = std.math.min(start, metadata.size());
            const e = std.math.min(end + 1, metadata.size());
            try buffer.content.append(try GapBuffer.init(allocator, buf[s..e]));

            end += 1;
            start = end;
        } else {
            end += 1;
        }
    }
    return buffer;
}

pub fn deinit(buffer: *Buffer) void {
    for (buffer.content.items) |gbuffer| {
        gbuffer.deinit();
    }
    buffer.content.deinit();
}

pub fn charAt(buffer: Buffer, row: i32, col: i32) ?u8 {
    if (buffer.content.items.len == 0) return null;
    var r = @intCast(usize, row - 1);
    var c = @intCast(usize, col - 1);
    return buffer.content.items[r].charAt(c);
}

pub fn moveCursorRelative(buffer: *Buffer, row_offset: i32, col_offset: i32) void {
    // print("{}\t{}\n", .{ cursor.row, cursor.col });
    if (buffer.content.items.len == 0) return;

    var new_row = buffer.cursor.row;
    var new_col = buffer.cursor.col;

    new_row += row_offset;
    new_col += col_offset;

    if (new_row <= 0) {
        new_row = 1;
    } else {
        new_row = std.math.min(new_row, buffer.content.items.len);
    }

    const gbuffer = buffer.content.items[@intCast(usize, new_row - 1)];
    if (new_col <= 0) {
        new_col = 1;
    } else {
        new_col = std.math.min(new_col, gbuffer.content.len - gbuffer.gap_size);
    }

    buffer.cursor.row = new_row;
    buffer.cursor.col = new_col;
}

pub fn moveCursorAbsolute(buffer: *Buffer, row: i32, col: i32) void {
    if (buffer.content.items.len == 0) return;
    var new_row = row;
    var new_col = col;

    if (new_row <= 0) {
        new_row = 1;
    } else {
        new_row = std.math.min(new_row, buffer.content.items.len);
    }

    const gbuffer = buffer.content.items[@intCast(usize, new_row - 1)];
    if (new_col <= 0) {
        new_col = 1;
    } else {
        new_col = std.math.min(new_col, gbuffer.content.len - gbuffer.gap_size);
    }

    buffer.cursor.row = new_row;
    buffer.cursor.col = new_col;
}

/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: i32, column: i32, string: []const u8) !void {
    if (row <= 0 or row >= buffer.content.items.len) {
        print("insert(): range out of bounds\n", .{});
        return;
    }

    var r = @intCast(usize, row - 1);
    var col = @intCast(i32, column - 1);
    var gbuffer = &buffer.content.items[r];

    gbuffer.moveGapPosAbsolute(col);
    try gbuffer.insert(string);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn delete(buffer: *Buffer, row: i32, start_column: i32, end_column: i32) !void {
    if (row <= 0 or row > buffer.content.items.len) {
        print("delete(): range out of bounds\n", .{});
        return;
    }
    var r = @intCast(usize, row - 1);
    var start_col = @intCast(i32, start_column - 1);
    var num_to_delete = @intCast(u32, end_column - start_col - 1);

    var gbuffer = &buffer.content.items[r];
    gbuffer.moveGapPosAbsolute(start_col);
    gbuffer.delete(num_to_delete);

    if (gbuffer.isEmpty()) {
        _ = buffer.content.orderedRemove(r);
        print("new size {}\n", .{buffer.content.items.len});

        // deleted the \n char
    } else if (gbuffer.getGapEndPos() == gbuffer.content.len - 1 and
        buffer.content.items.len >= 2 and
        r < buffer.content.items.len - 1)
    { // merge this line with the next
        var gb = buffer.content.orderedRemove(r + 1);
        defer gb.deinit();
        var str = try gb.getContent();
        try buffer.insert(row, @intCast(i32, gbuffer.content.len), str);
    }
}

pub fn deleteRows(buffer: *Buffer, start_row: i32, end_row: i32) !void {
    if (start_row > buffer.content.items.len) return;
    var line = buffer.content.orderedRemove(@intCast(usize, start_row - 1));
    buffer.allocator.free(line.content);
    _ = end_row;
}

// pub fn deleteRange(buffer: *Buffer, start_row: i32, end_row: i32, start_col: i32, end_col: i32) !void {
// }
