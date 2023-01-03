const std = @import("std");
const print = std.debug.print;

const utf8 = @import("utf8.zig");

pub fn FixedArray(comptime T: type) type {
    return struct {
        const Self = @This();

        array: []T,
        capacity: u64,

        pub fn init(array: []T) Self {
            return Self{
                .array = array,
                .capacity = array.len,
            };
        }

        pub fn slice(fixed_array: *Self) []T {
            return fixed_array.array[0..fixed_array.lastElementIndex()];
        }

        pub fn append(fixed_array: *Self, element: T) !void {
            if (fixed_array.capacity == 0) return error.NoMoreSpaceInArray;

            fixed_array.array[fixed_array.lastElementIndex()] = element;
            fixed_array.capacity -= 1;
        }

        pub fn pop(fixed_array: *Self) !T {
            if (fixed_array.empty()) return error.EmptyArray;

            const index = fixed_array.lastElementIndex();
            fixed_array.capacity += 1;
            return fixed_array.array[index];
        }

        pub fn remove(fixed_array: *Self, index: u64) T {
            if (index >= fixed_array.lastElementIndex()) return fixed_array.pop() catch unreachable;
            var element = fixed_array.array[index];
            for (fixed_array.array[index + 1 ..]) |e, i|
                fixed_array.array[index + i] = e;

            fixed_array.capacity += 1;
            return element;
        }

        pub fn lastElementIndex(fixed_array: *Self) u64 {
            return fixed_array.array.len - fixed_array.capacity;
        }

        pub fn empty(fixed_array: *Self) bool {
            return fixed_array.capacity == fixed_array.array.len;
        }

        pub fn full(fixed_array: *Self) bool {
            return fixed_array.capacity == 0;
        }
    };
}

pub fn assert(ok: bool, comptime message: []const u8) void {
    if (!ok) {
        print("{s}\n", .{message});
        unreachable;
    }
}

pub fn minOrMax(comptime T: type, value: T, min: T, max: T) T {
    return if (value <= min)
        min
    else if (value >= max)
        max
    else
        value;
}

pub fn countChar(string: []const u8, char: u8) u32 {
    var count: u32 = 0;
    for (string) |c| {
        if (c == char) count += 1;
    }
    return count;
}

pub fn typeToString(buf: []u8, T: anytype) ![]const u8 {
    return std.fmt.bufPrint(buf, "{}", .{T});
}

pub fn typeToStringAlloc(allocator: std.mem.Allocator, T: anytype) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{}", .{T});
}

pub fn splitAfter(comptime T: type, buffer: []const T, delimiter: T) SplitAfterIterator(T) {
    return .{
        .buffer = buffer,
        .start_index = 0,
        .end_index = 0,
        .delimiter = delimiter,
    };
}

pub fn SplitAfterIterator(comptime T: type) type {
    return struct {
        buffer: []const T,
        start_index: usize,
        end_index: usize,
        delimiter: T,

        const Self = @This();

        /// Returns a slice of the next field, or null if splitting is complete.
        pub fn next(self: *Self) ?[]const T {
            var i: usize = self.start_index;
            while (i < self.buffer.len) {
                var element = self.buffer[i];
                if (element == self.delimiter or i == self.buffer.len - 1) {
                    const s = std.math.min(self.start_index, self.buffer.len);
                    const e = std.math.min(self.end_index + 1, self.buffer.len);
                    var slice = self.buffer[s..e];

                    self.end_index += 1;
                    self.start_index = self.end_index;
                    return slice;
                } else {
                    self.end_index += 1;
                    i += 1;
                }
            }
            return null;
        }
    };
}

/// Takes three numbers and returns true if the first number is in the range
/// of the second and third numbers
pub fn inRange(comptime T: type, a: T, b: T, c: T) bool {
    return a >= b and a <= c;
}

pub fn abs(val: f32) f32 {
    return if (val < 0) -val else val;
}

pub fn fileLocation(comptime location: std.builtin.SourceLocation) []const u8 {
    return location.file ++ " | " ++ location.fn_name ++ ": ";
}
