const std = @import("std");

const editor_api = @import("../editor/editor.zig");
const Buffer = editor_api.Buffer;
const BufferWindow = editor_api.BufferWindow;

pub const BufferDisplayer = @This();

ptr: *anyopaque,
vtable: *const VTable,

// pub fn init(self: BufferDisplayer, allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
// try self.vtable.init(allocator);
// }

pub fn info(self: BufferDisplayer, allocator: std.mem.Allocator, buffer_window: *BufferWindow, buffer: *Buffer, window_height: f32) std.mem.Allocator.Error![]RowInfo {
    return self.vtable.info(self.ptr, allocator, buffer_window, buffer, window_height);
}

// pub fn deinit(self: BufferDisplayer, allocator: std.mem.Allocator) void {
//     self.vtable.deinit(allocator);
// }

const VTable = struct {
    // init: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) std.mem.Allocator.Error!void,
    info: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, buffer_window: *BufferWindow, buffer: *Buffer, window_height: f32) std.mem.Allocator.Error![]RowInfo,
    // deinit: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
};

pub const ColorRange = struct {
    pub fn lessThan(comptime context: type, a: BufferDisplayer.ColorRange, b: BufferDisplayer.ColorRange) bool {
        _ = context;
        return a.start < b.start;
    }

    start: u64,
    end: u64,
    color: u32,

    pub const ColorRangeIterator = struct {
        start: u64,
        end: u64,
        line_len: u64,
        i: u64,
        color_ranges: []ColorRange,
        defualt_color: u32,

        pub fn init(defualt_color: u32, line_len: u64, color_ranges: []ColorRange) ColorRangeIterator {
            var end: u64 = if (color_ranges.len == 0)
                line_len
            else if (color_ranges[0].start == 0)
                color_ranges[0].end
            else
                color_ranges[0].start;
            return .{
                .start = 0,
                .end = end,
                .line_len = line_len,
                .i = 0,
                .color_ranges = color_ranges,
                .defualt_color = defualt_color,
            };
        }

        pub fn next(self: *ColorRangeIterator) ?ColorRange {
            if (self.start >= self.line_len) return null;
            if (self.color_ranges.len == 0 or self.i >= self.color_ranges.len) {
                const start = self.start;
                self.start = self.line_len;
                return .{ .start = start, .end = self.line_len, .color = self.defualt_color };
            }

            const is_color_range = self.color_ranges[self.i].start == self.start and self.color_ranges[self.i].end == self.end;
            const next_color_range: ?ColorRange =
                if (self.i + 1 < self.color_ranges.len)
                self.color_ranges[self.i + 1]
            else
                null;

            const new_start = self.end;
            const new_end = blk: {
                if (is_color_range) {
                    if (next_color_range) |n| break :blk n.start;
                    break :blk self.line_len;
                } else {
                    break :blk self.color_ranges[self.i].end;
                }
            };

            const color = if (is_color_range)
                self.color_ranges[self.i].color
            else
                self.defualt_color;

            const result = ColorRange{ .start = self.start, .end = self.end, .color = color };

            self.start = new_start;
            self.end = new_end;
            if (is_color_range) self.i += 1;

            return result;
        }
    };
};

pub const RowInfo = struct {
    color_ranges: []ColorRange,
    row: u64,
    size: f32,
};
