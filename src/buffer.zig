const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;

const Cursor = @import("cursor.zig").Cursor;
const GapBuffer = @import("gap_buffer.zig").GapBuffer;

const Buffer = @This();

cursor: Cursor,
lines: GapBuffer(GapBuffer(u8)),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, file_name: []const u8) !*Buffer {
    var buffer = try allocator.create(Buffer);
    buffer.lines = try GapBuffer(GapBuffer(u8)).init(allocator, null);
    buffer.cursor = .{ .row = 1, .col = 1 };
    buffer.allocator = allocator;

    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();
    const metadata = try file.metadata();
    try file.seekTo(0);
    var buf = try file.readToEndAlloc(allocator, metadata.size());
    defer allocator.free(buf);

    buffer.lines.moveGapPosAbsolute(0);
    var start: usize = 0;
    var end: usize = 0;
    for (buf) |char| {
        if (char == '\n') {
            const s = std.math.min(start, metadata.size());
            const e = std.math.min(end + 1, metadata.size());
            try buffer.lines.insertOne(try GapBuffer(u8).init(allocator, buf[s..e]));

            end += 1;
            start = end;
        } else {
            end += 1;
        }
    }
    buffer.lines.moveGapPosAbsolute(0);

    return buffer;
}

pub fn deinit(buffer: *Buffer) void {
    var lines = buffer.lines;
    lines.moveGapPosAbsolute(0);
    var i: usize = 0;
    while (i < lines.getLength()) : (i += 1) {
        lines.content[i + lines.getGapEndPos() + 1].deinit();
    }
    buffer.lines.deinit();
    buffer.allocator.destroy(buffer);
}

pub fn charAt(buffer: Buffer, row: i32, col: i32) ?u8 {
    if (buffer.lines.getLength() == 0) return null;
    var r = @intCast(usize, row - 1);
    var c = @intCast(usize, col - 1);

    var gbuffer = buffer.lines.elementAt(r).?;
    if (c >= gbuffer.content.getLength()) return null;
    return gbuffer.elementAt(c).*;
}

pub fn moveCursorRelative(buffer: *Buffer, row_offset: i32, col_offset: i32) void {
    // print("{}\t{}\n", .{ cursor.row, cursor.col });
    if (buffer.lines.getLength() == 0) return;

    var new_row = buffer.cursor.row;
    var new_col = buffer.cursor.col;

    new_row += row_offset;
    new_col += col_offset;

    if (new_row <= 0) {
        new_row = 1;
    } else {
        new_row = std.math.min(new_row, buffer.lines.getLength());
    }

    const gbuffer = buffer.lines.elementAt(@intCast(usize, new_row - 1));
    if (new_col <= 0) {
        new_col = 1;
    } else {
        new_col = std.math.min(new_col, gbuffer.getLength());
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
        new_row = std.math.min(new_row, buffer.lines.getLength());
    }

    const gbuffer = buffer.lines.elementAt(@intCast(usize, new_row - 1)).?;
    if (new_col <= 0) {
        new_col = 1;
    } else {
        new_col = std.math.min(new_col, gbuffer.getLength());
    }

    buffer.cursor.row = new_row;
    buffer.cursor.col = new_col;
}

/// Inserts the given string at the given row and column. (1-based)
pub fn insert(buffer: *Buffer, row: i32, column: i32, string: []const u8) !void {
    if (row <= 0 or row >= buffer.lines.getLength()) {
        print("insert(): range out of bounds\n", .{});
        return;
    }

    var r = @intCast(usize, row - 1);
    var c = @intCast(i32, column - 1);
    var gbuffer = buffer.lines.elementAt(r);

    gbuffer.moveGapPosAbsolute(c);
    try gbuffer.insertMany(string);
}

/// deletes the string at the given row from start_column to end_column (exclusive). (1-based)
pub fn delete(buffer: *Buffer, row: i32, start_column: i32, end_column: i32) !void {
    if (row <= 0 or row > buffer.lines.getLength()) {
        print("delete(): range out of bounds\n", .{});
        return;
    }
    var lines = &buffer.lines;
    var r = @intCast(usize, row - 1);
    var start_col = @intCast(i32, start_column - 1);
    var num_to_delete = @intCast(u32, end_column - start_col - 1);

    var gbuffer = lines.elementAt(r);

    gbuffer.moveGapPosAbsolute(start_col);
    gbuffer.delete(num_to_delete);

    if (gbuffer.isEmpty()) {
        lines.elementAt(r).deinit();
        lines.moveGapPosAbsolute(@intCast(i32, r));
        lines.delete(1);
        print("new size {}\n", .{lines.getLength()});

        // deleted the \n char
    } else if (gbuffer.getGapEndPos() == gbuffer.content.len - 1 and
        lines.getLength() >= 2 and
        r < lines.getLength() - 1)
    { // merge this line with the next
        try buffer.mergeLines(r, r + 1);
        lines.moveGapPosAbsolute(@intCast(i32, r + 1));
        lines.delete(1);
    }
}

/// Merges the contents of two lines
pub fn mergeLines(buffer: *Buffer, first_row: usize, second_row: usize) !void {
    var next_line = buffer.lines.elementAt(second_row);

    var str = try next_line.getContent();

    var gbuffer = buffer.lines.elementAt(first_row);
    try gbuffer.insertMany(str);

    buffer.allocator.free(str);
    buffer.allocator.free(next_line.content);
}

pub fn deleteRows(buffer: *Buffer, start_row: i32, end_row: i32) !void {
    if (start_row > buffer.content.items.len) return;
    _ = start_row;
    _ = end_row;
    // TODO: this
}

// pub fn deleteRange(buffer: *Buffer, start_row: i32, end_row: i32, start_col: i32, end_col: i32) !void {
// }
