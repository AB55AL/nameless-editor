const globals = @import("../globals.zig");

pub fn extraFrame() void {
    globals.internal.extra_frame = true;
}

pub fn addUserUI(func: globals.UserUIFunc) void {
    _ = globals.ui.user_ui.getOrPut(func) catch return;
}

pub fn removeUserUI(func: globals.UserUIFunc) void {
    _ = globals.ui.user_ui.remove(func);
}
