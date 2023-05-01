const std = @import("std");
const print = std.debug.print;

const gui = @import("gui");

const editor = @import("../globals.zig").editor;
const ui = @import("../globals.zig").ui;
const utils = @import("../utils.zig");

pub const Notify = struct {
    title: []const u8,
    message: []const u8,
    /// Remaining time in seconds
    remaining_time: f32,
    duplicates: u32,
};

pub const Notifications = struct {
    const HashContext = struct {
        pub fn hash(self: HashContext, data: Notify) u32 {
            _ = self;
            var wh = std.hash.Wyhash.init(0);
            wh.update(data.title);
            wh.update(data.message);
            return @truncate(u32, wh.final());
        }

        pub fn eql(self: HashContext, a: Notify, b: Notify, b_index: usize) bool {
            _ = b_index;
            _ = self;
            return std.mem.eql(u8, a.title, b.title) and std.mem.eql(u8, a.message, b.message);
        }
    };
    const Set = std.ArrayHashMapUnmanaged(Notify, void, HashContext, false);
    data: Set = .{},
    arena_instance: std.heap.ArenaAllocator,

    pub fn init() Notifications {
        return .{
            .arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *Notifications) void {
        self.arena_instance.deinit();
        self.data = .{};
    }

    pub fn add(self: *Notifications, comptime title_fmt: []const u8, title_values: anytype, comptime message_fmt: []const u8, message_values: anytype, time: f32) !void {
        const arena = self.arena_instance.allocator();

        var title = try std.fmt.allocPrint(arena, title_fmt, title_values);
        var message = try std.fmt.allocPrint(arena, message_fmt, message_values);

        const notification = Notify{ .title = title, .message = message, .remaining_time = time, .duplicates = 0 };
        var noti = self.data.getKeyPtr(notification);
        if (noti) |n| {
            n.duplicates +|= 1;
            n.remaining_time = time;
        } else {
            _ = try self.data.getOrPut(arena, notification);
        }
    }

    pub fn clearDone(self: *Notifications, nstime_since_last_frame: u64) void {
        if (self.data.count() == 0) return;

        const second_diff = @intToFloat(f32, nstime_since_last_frame) / 1000000000;
        var iter = self.data.iterator();
        while (iter.next()) |kv| {
            var noti = kv.key_ptr;
            noti.remaining_time -= second_diff;

            if (noti.remaining_time <= 0) {
                _ = self.data.orderedRemove(noti.*);
                // keep the iterator in place
                iter.index -|= 1;
                iter.len -|= 1;
            }
        }

        if (self.data.count() == 0) self.reset();
    }

    pub fn count(self: *Notifications) u64 {
        return self.data.count();
    }

    fn reset(self: *Notifications) void {
        _ = self.arena_instance.reset(.free_all);
        self.data = .{};
    }
};
