const std = @import("std");
const print = std.debug.print;

const stdout = std.io.getStdOut();

pub fn GapBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        gap_pos: u32,
        gap_size: u32,
        /// The entire contents of the GapBuffer including the gap
        /// To get the length of the contents without the gap use length()
        content: []T,

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, input: ?[]const T) !Self {
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

        pub fn replaceAllWith(gbuffer: *Self, new_content: []const T) !void {
            gbuffer.moveGapPosAbsolute(0);
            const end_of_line = std.math.maxInt(i32);
            gbuffer.delete(end_of_line);
            try gbuffer.insertMany(new_content);
        }

        /// deletes a given number of elements after the gap_pos
        pub fn delete(gbuffer: *Self, num: i32) void {
            if (num < 0) {
                print("Can't pass negative numbers to GapBuffer.delete()", .{});
                return;
            }
            var n = std.math.min(num, (gbuffer.content.len - 1) - gbuffer.getGapEndPos());
            gbuffer.gap_size += @intCast(u32, n);
        }

        /// Moves the gap to before the index
        pub fn moveGapPosAbsolute(gbuffer: *Self, index: i32) void {
            if (index < 0 or index == gbuffer.gap_pos) return;

            var i: i32 = index - @intCast(i32, gbuffer.gap_pos);
            gbuffer.moveGapPosRelative(i);
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
        pub fn copyOfContent(gbuffer: *Self) ![]T {
            var content = try gbuffer.allocator.alloc(T, gbuffer.content.len - gbuffer.gap_size);
            gbuffer.moveGapPosAbsolute(0);

            var i: usize = 0;
            while (i < gbuffer.length()) : (i += 1) {
                gbuffer.moveGapPosAbsolute(0);
                content[i] = gbuffer.content[i + gbuffer.getGapEndPos() + 1];
            }
            return content;
        }

        /// Returns a slice containing the content.
        /// DOES NOT CREATE A COPY.
        /// If the gap moves It **WILL** modify the content of the slice since the slice is just a pointer into an array
        pub fn sliceOfContent(gbuffer: *Self) []T {
            gbuffer.moveGapPosAbsolute(0);
            return gbuffer.content[gbuffer.getGapEndPos() + 1 ..];
        }

        /// returns a pointer to the ith element
        /// moves the gap out of the way
        pub fn elementAt(gbuffer: *Self, index: usize) *T {
            gbuffer.moveGapPosAbsolute(0);
            // print("index = {} and gap_pos {} and content.len {}\n", .{ index, index + gbuffer.getGapEndPos() + 1, gbuffer.content.len });
            var i = std.math.min(index + gbuffer.getGapEndPos() + 1, gbuffer.content.len - 1);
            return &gbuffer.content[i];
        }

        pub fn getGapEndPos(gbuffer: *Self) u32 {
            return gbuffer.gap_pos + gbuffer.gap_size - 1;
        }

        pub fn isEmpty(gbuffer: *Self) bool {
            return gbuffer.content.len == gbuffer.gap_size;
        }

        /// Returns the length of the content without the gap size
        pub fn length(gbuffer: Self) usize {
            return gbuffer.content.len - gbuffer.gap_size;
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
