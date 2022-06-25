const std = @import("std");
const print = std.debug.print;

const stdout = std.io.getStdOut();

const GapBuffer = @This();

gap_pos: u32,
gap_size: u32,
content: []u8,

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, buffer: []u8) !GapBuffer {
    const gap_size = 16;
    const gap_pos = 0;
    var content = try allocator.alloc(u8, buffer.len + gap_size);

    var i: usize = gap_size;
    for (buffer) |char| {
        content[i] = char;
        i += 1;
    }

    return GapBuffer{
        .gap_pos = gap_pos,
        .gap_size = gap_size,
        .content = content,
        .allocator = allocator,
    };
}

pub fn deinit(gbuffer: GapBuffer) void {
    gbuffer.allocator.free(gbuffer.content);
    gbuffer.allocator.destroy(&gbuffer);
}

pub fn insert(gbuffer: *GapBuffer, string: []const u8) !void {
    var i: usize = 0;
    while (i < string.len) : (i += 1) {
        if (gbuffer.gap_size == 0) try gbuffer.resizeGap();

        gbuffer.content[gbuffer.gap_pos] = string[i];
        gbuffer.gap_pos += 1;
        gbuffer.gap_size -= 1;
    }

    if (gbuffer.gap_size == 0) try gbuffer.resizeGap();
}

pub fn delete(gbuffer: *GapBuffer, num: u32) void {
    var n = std.math.min(num, (gbuffer.content.len - 1) - gbuffer.getGapEndPos());
    gbuffer.gap_size += n;
}

pub fn moveGapPosAbsolute(gbuffer: *GapBuffer, column: i32) void {
    if (column < 0 or column == gbuffer.gap_pos) return;

    var col: i32 = column - @intCast(i32, gbuffer.gap_pos);
    gbuffer.moveGapPosRelative(col);
}

pub fn moveGapPosRelative(gbuffer: *GapBuffer, offset: i32) void {
    if (offset < 0 and gbuffer.gap_pos == 0) return;
    if (offset > 0 and gbuffer.getGapEndPos() == gbuffer.content.len - 1) return;

    if (offset > 0) { // moving to the right
        var i: i32 = if (@intCast(i32, gbuffer.getGapEndPos()) + offset >= gbuffer.content.len)
            @intCast(i32, (gbuffer.content.len - 1) - gbuffer.getGapEndPos())
        else
            offset;

        while (i != 0) : (i -= 1) {
            gbuffer.content[gbuffer.gap_pos] = gbuffer.content[gbuffer.getGapEndPos() + 1];
            gbuffer.gap_pos += 1;
        }
    } else if (offset < 0) { // moving to the left
        var i: i32 = if (@intCast(i32, gbuffer.gap_pos) + offset < 0)
            -@intCast(i32, gbuffer.gap_pos) // negate the value after cast
        else
            offset;

        while (i != 0) : (i += 1) {
            gbuffer.content[gbuffer.getGapEndPos()] = gbuffer.content[gbuffer.gap_pos - 1];
            gbuffer.gap_pos -= 1;
        }
    }
}

pub fn printContent(gbuffer: *GapBuffer) void {
    var i: usize = 0;
    while (i < gbuffer.content.len) : (i += 1) {
        if (i == gbuffer.gap_pos) i += gbuffer.gap_size;
        if (i >= gbuffer.content.len) break;
        print("{c}", .{gbuffer.content[i]});
    }
}

pub fn getContent(gbuffer: *GapBuffer) ![]u8 {
    var str = try gbuffer.allocator.alloc(u8, gbuffer.content.len - gbuffer.gap_size);
    var i: usize = 0;
    var j: usize = 0;
    while (i < gbuffer.content.len) : (i += 1) {
        if (i == gbuffer.gap_pos) i += gbuffer.gap_size;
        if (i >= gbuffer.content.len) break;
        str[j] = gbuffer.content[i];
        j += 1;
    }

    return str;
}

pub fn charAt(gbuffer: GapBuffer, index: usize) ?u8 {
    var i: usize = 0;
    var j: usize = 0;
    while (i <= gbuffer.content.len) : (i += 1) {
        if (i == gbuffer.gap_pos) i += gbuffer.gap_size;
        if (i >= gbuffer.content.len) break;

        if (j == index) return gbuffer.content[j + gbuffer.gap_size];
        j += 1;
    }

    return null;
}

fn resizeGap(gbuffer: *GapBuffer) !void {
    var new_gap_size: u32 = 16;
    var content = try gbuffer.allocator.alloc(u8, gbuffer.content.len + new_gap_size);

    var i: usize = 0;
    for (gbuffer.content) |char| {
        if (i == gbuffer.gap_pos) i += new_gap_size;
        content[i] = char;
        i += 1;
    }

    gbuffer.allocator.free(gbuffer.content);

    gbuffer.content = content;
    gbuffer.gap_size = new_gap_size;
}

pub fn getGapEndPos(gbuffer: *GapBuffer) u32 {
    return gbuffer.gap_pos + gbuffer.gap_size - 1;
}

pub fn isEmpty(gbuffer: *GapBuffer) bool {
    return gbuffer.content.len == gbuffer.gap_size;
}
