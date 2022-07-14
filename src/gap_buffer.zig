const std = @import("std");
const print = std.debug.print;

const stdout = std.io.getStdOut();

pub const GapBuffer = @This();

gap_pos: usize,
gap_size: usize,
/// The entire contents of the GapBuffer including the gap
/// To get the length of the contents without the gap use length()
content: []u8,

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, input: ?[]const u8) !GapBuffer {
    const gap_size: u32 = 16;
    const gap_pos = 0;
    const size = if (input) |in| in.len else 0;
    var content = try allocator.alloc(u8, size + gap_size);

    if (input) |in| {
        for (in) |element, i|
            content[i + gap_size] = element;
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

/// deletes a given number of elements after the gap_pos
pub fn delete(gbuffer: *GapBuffer, num: usize) void {
    var n = std.math.min(num, (gbuffer.content.len - 1) - gbuffer.gapEndPos());
    gbuffer.gap_size += n;
}

pub fn replaceAllWith(gbuffer: *GapBuffer, new_content: []const u8) !void {
    gbuffer.moveGapPosAbsolute(0);
    gbuffer.delete(gbuffer.length());
    try gbuffer.insert(new_content);
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
pub fn sliceOfContent(gbuffer: *GapBuffer) []u8 {
    gbuffer.moveGapPosAbsolute(gbuffer.length());
    return gbuffer.content[0..gbuffer.gap_pos];
}

/// returns the ith byte
/// moves the gap out of the way
pub fn byteAt(gbuffer: *GapBuffer, index: usize) u8 {
    gbuffer.moveGapPosAbsolute(gbuffer.length());
    return gbuffer.content[index];
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
