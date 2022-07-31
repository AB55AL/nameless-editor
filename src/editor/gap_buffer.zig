const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const max = std.math.max;

const stdout = std.io.getStdOut();

pub const GapBuffer = @This();

gap_pos: usize,
gap_size: usize,
/// The entire contents of the GapBuffer including the gap
/// To get the length of the contents without the gap use length()
content: []u8,

/// The number of lines in the gap_buffer
count: u32,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, input: ?[]const u8) !GapBuffer {
    const size = if (input) |in| in.len else 0;
    const gap_pos = 0;
    const gap_size: u32 = @floatToInt(u32, max(16, @intToFloat(f32, size) * 0.01));

    var content = try allocator.alloc(u8, size + gap_size);
    var nl_count: u32 = 0;

    if (input) |in| {
        @setRuntimeSafety(false);
        for (in) |b, i| {
            content[i + gap_size] = b;
            if (b == '\n') nl_count += 1;
        }
    }

    return GapBuffer{
        .gap_pos = gap_pos,
        .gap_size = gap_size,
        .content = content,
        .allocator = allocator,
        .count = nl_count,
    };
}

pub fn deinit(gbuffer: GapBuffer) void {
    gbuffer.allocator.free(gbuffer.content);
}

/// Inserts a slice at the gap_pos.
/// resizes the gap when needed
pub fn insert(gbuffer: *GapBuffer, content: []const u8) !void {
    @setRuntimeSafety(false);
    for (content) |element| {
        if (gbuffer.gap_size == 0) try gbuffer.resizeGap();

        gbuffer.content[gbuffer.gap_pos] = element;
        gbuffer.gap_pos += 1;
        gbuffer.gap_size -= 1;
    }

    if (gbuffer.gap_size == 0) try gbuffer.resizeGap();
}

/// Inserts a slice at the index.
/// resizes the gap when needed
pub fn insertAt(gbuffer: *GapBuffer, index: usize, content: []const u8) !void {
    gbuffer.moveGapPosAbsolute(index);
    try gbuffer.insert(content);
}

/// deletes a given number of elements after the gap_pos
pub fn delete(gbuffer: *GapBuffer, num: usize) void {
    var n = std.math.min(num, (gbuffer.content.len - 1) - gbuffer.gapEndPos());
    gbuffer.gap_size += n;
}

/// deletes a given number of elements after the index
pub fn deleteAfter(gbuffer: *GapBuffer, index: usize, num: usize) void {
    gbuffer.moveGapPosAbsolute(index);
    gbuffer.delete(num);
}

pub fn replaceAllWith(gbuffer: *GapBuffer, new_content: []const u8) !void {
    gbuffer.moveGapPosAbsolute(0);
    gbuffer.delete(gbuffer.length());
    try gbuffer.insert(new_content);
}

pub fn prepend(gbuffer: *GapBuffer, string: []const u8) !void {
    gbuffer.moveGapPosAbsolute(0);
    try gbuffer.insert(string);
}

pub fn append(gbuffer: *GapBuffer, string: []const u8) !void {
    gbuffer.moveGapPosAbsolute(gbuffer.length());
    try gbuffer.insert(string);
}

/// Moves the gap to before the index
pub fn moveGapPosAbsolute(gbuffer: *GapBuffer, index: usize) void {
    if (index == gbuffer.gap_pos) return;
    var i: i64 = @intCast(i64, index) - @intCast(i64, gbuffer.gap_pos);
    gbuffer.moveGapPosRelative(i);
}

pub fn moveGapPosRelative(gbuffer: *GapBuffer, offset: i64) void {
    if (offset < 0 and gbuffer.gap_pos == 0) return;
    if (offset > 0 and gbuffer.gapEndPos() == gbuffer.content.len - 1) return;

    if (offset > 0) { // moving to the right
        var i: i64 = if (@intCast(i64, gbuffer.gapEndPos()) + offset >= gbuffer.content.len)
            @intCast(i64, (gbuffer.content.len - 1) - gbuffer.gapEndPos())
        else
            offset;

        while (i != 0) : (i -= 1) {
            gbuffer.content[gbuffer.gap_pos] = gbuffer.content[gbuffer.gapEndPos() + 1];
            gbuffer.gap_pos += 1;
        }
    } else if (offset < 0) { // moving to the left
        var i: i64 = if (@intCast(i64, gbuffer.gap_pos) + offset < 0)
            -@intCast(i64, gbuffer.gap_pos) // negate the value after cast
        else
            offset;

        while (i != 0) : (i += 1) {
            gbuffer.content[gbuffer.gapEndPos()] = gbuffer.content[gbuffer.gap_pos - 1];
            gbuffer.gap_pos -= 1;
        }
    }
}

/// Allocates a copy
/// Caller owns memory
pub fn copy(gbuffer: *GapBuffer) ![]u8 {
    var content = try gbuffer.allocator.alloc(u8, gbuffer.content.len - gbuffer.gap_size);
    gbuffer.moveGapPosAbsolute(gbuffer.length());

    @setRuntimeSafety(false);
    for (content) |_, i| {
        gbuffer.moveGapPosAbsolute(gbuffer.length());
        content[i] = gbuffer.content[i];
    }
    return content;
}

/// Returns a slice containing the content.
/// DOES NOT CREATE A COPY.
/// If the gap moves It **WILL** modify the content of the slice.
pub fn slice(gbuffer: *GapBuffer, from: usize, to: usize) []const u8 {
    assert(from <= to);
    assert(to <= gbuffer.length());

    if (to <= gbuffer.gap_pos)
        return gbuffer.content[from..to];

    // calculate the smallest distance that the gap needs to move
    const left = @intCast(i64, gbuffer.gap_pos) - @intCast(i64, from);
    const right = @intCast(i64, to - gbuffer.gap_pos);

    if (left < right) {
        gbuffer.moveGapPosRelative(-left);
        return gbuffer.content[from + gbuffer.gap_size .. to + gbuffer.gap_size];
    } else {
        gbuffer.moveGapPosRelative(right);
        return gbuffer.content[from..to];
    }
}

/// returns the ith byte
/// moves the gap out of the way
pub fn byteAt(gbuffer: *GapBuffer, index: usize) u8 {
    if (index < gbuffer.gap_pos)
        return gbuffer.content[index]
    else
        return gbuffer.content[index - gbuffer.gap_pos];
}

pub fn gapEndPos(gbuffer: *GapBuffer) usize {
    return gbuffer.gap_pos + gbuffer.gap_size - 1;
}

pub fn isEmpty(gbuffer: *GapBuffer) bool {
    return gbuffer.content.len == gbuffer.gap_size;
}

/// Returns the length of the content without the gap size
pub fn length(gbuffer: *GapBuffer) usize {
    return gbuffer.content.len - gbuffer.gap_size;
}

fn resizeGap(gbuffer: *GapBuffer) !void {
    var size = @intToFloat(f32, gbuffer.content.len) * 0.01;
    var new_gap_size: u32 = std.math.max(16, @floatToInt(u32, size));
    var content = try gbuffer.allocator.alloc(u8, gbuffer.content.len + new_gap_size);

    @setRuntimeSafety(false);
    var i: usize = 0;
    for (gbuffer.content) |element| {
        if (i == gbuffer.gap_pos) i += new_gap_size;
        content[i] = element;
        i += 1;
    }

    gbuffer.allocator.free(gbuffer.content);

    gbuffer.content = content;
    gbuffer.gap_size = new_gap_size;
}
