const std = @import("std");
const print = std.debug.print;

const stdout = std.io.getStdOut();

pub fn GapBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        gap_pos: u32,
        gap_size: u32,
        content: []T,

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, input: ?[]T) !Self {
            const gap_size: u32 = 16;
            const gap_pos = 0;
            const size = if (input != null) input.?.len else 0;
            var content = try allocator.alloc(T, size + gap_size);

            if (input != null) {
                for (input.?) |element, i| {
                    content[i + gap_size] = element;
                }
            }

            return Self{
                .gap_pos = gap_pos,
                .gap_size = gap_size,
                .content = content,
                .allocator = allocator,
            };
        }

        pub fn deinit(gbuffer: Self) void {
            gbuffer.allocator.free(gbuffer.content);
        }

        /// Inserts a slice at the gap_pos.
        /// resizes the gap when needed
        pub fn insertMany(gbuffer: *Self, content: []const T) !void {
            @setRuntimeSafety(false);
            for (content) |element| {
                if (gbuffer.gap_size == 0) try gbuffer.resizeGap();

                gbuffer.content[gbuffer.gap_pos] = element;
                gbuffer.gap_pos += 1;
                gbuffer.gap_size -= 1;
            }

            if (gbuffer.gap_size == 0) try gbuffer.resizeGap();
        }

        /// Inserts one element at the gap_pos.
        /// resizes the gap when needed
        pub fn insertOne(gbuffer: *Self, element: T) !void {
            if (gbuffer.gap_size == 0) try gbuffer.resizeGap();

            gbuffer.content[gbuffer.gap_pos] = element;
            gbuffer.gap_pos += 1;
            gbuffer.gap_size -= 1;

            if (gbuffer.gap_size == 0) try gbuffer.resizeGap();
        }

        /// deletes a given number of elements after the gap_pos
        pub fn delete(gbuffer: *Self, num: u32) void {
            var n = std.math.min(num, (gbuffer.content.len - 1) - gbuffer.getGapEndPos());
            gbuffer.gap_size += n;
        }

        pub fn moveGapPosAbsolute(gbuffer: *Self, column: i32) void {
            if (column < 0 or column == gbuffer.gap_pos) return;

            var col: i32 = column - @intCast(i32, gbuffer.gap_pos);
            gbuffer.moveGapPosRelative(col);
        }

        pub fn moveGapPosRelative(gbuffer: *Self, offset: i32) void {
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

        /// Prints the contents to stderr
        pub fn printContent(gbuffer: Self, comptime fmt: []const u8) void {
            var i: usize = 0;
            while (true) : (i += 1) {
                if (i == gbuffer.gap_pos) i += gbuffer.gap_size;
                if (i >= gbuffer.content.len) break;
                print(fmt, .{gbuffer.content[i]});
            }
        }

        /// Allocates a new slice containing the contents and returns it
        pub fn getContent(gbuffer: *Self) ![]T {
            var str = try gbuffer.allocator.alloc(T, gbuffer.content.len - gbuffer.gap_size);
            var i: usize = 0;
            var j: usize = 0;
            while (true) : (i += 1) {
                if (i == gbuffer.gap_pos) i += gbuffer.gap_size;
                if (i >= gbuffer.content.len) break;
                str[j] = gbuffer.content[i];
                j += 1;
            }

            return str;
        }

        /// returns the ith element or null
        /// jumps over the gap
        pub fn elementAt(gbuffer: Self, index: usize) ?T {
            @setRuntimeSafety(false);
            var i: usize = 0;
            var j: usize = 0;
            while (true) : (i += 1) {
                if (i == gbuffer.gap_pos) i += gbuffer.gap_size;
                if (i >= gbuffer.content.len) break;

                if (j == index) return gbuffer.content[j + gbuffer.gap_size];
                j += 1;
            }

            return null;
        }

        pub fn getGapEndPos(gbuffer: *Self) u32 {
            return gbuffer.gap_pos + gbuffer.gap_size - 1;
        }

        pub fn isEmpty(gbuffer: *Self) bool {
            return gbuffer.content.len == gbuffer.gap_size;
        }

        fn resizeGap(gbuffer: *Self) !void {
            var size = @intToFloat(f32, gbuffer.content.len) * 0.01;
            var new_gap_size: u32 = std.math.max(16, @floatToInt(u32, size));
            var content = try gbuffer.allocator.alloc(T, gbuffer.content.len + new_gap_size);

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
    };
}
