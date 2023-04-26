const std = @import("std");

const globals = @import("../globals.zig");

pub const UserUI = *const fn (gpa: std.mem.Allocator, arena: std.mem.Allocator) void;

pub fn extraFrame() void {
    globals.internal.extra_frame = true;
}

pub fn addUserUI(func: UserUI) void {
    _ = globals.ui.user_ui.getOrPut(globals.internal.allocator, func) catch return;
}

pub fn removeUserUI(func: UserUI) void {
    _ = globals.ui.user_ui.remove(func);
}
